"""
Сканирование и индексация скиллов.

Обходит директорию skills/, парсит SKILL.md, вычисляет completeness.
"""

import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

from . import store

DEFAULT_SKILLS_DIR = "/Users/user/orchestra/skills/"


def full_reindex(skills_dir=None):
    """
    Полное сканирование директории скиллов.

    Для каждой папки первого уровня с SKILL.md:
    - Парсит метаданные
    - Вычисляет completeness
    - Считает file_count и last_modified

    Возвращает количество проиндексированных скиллов.
    """
    skills_dir = Path(skills_dir or DEFAULT_SKILLS_DIR)
    if not skills_dir.exists():
        return 0

    skills = []
    for entry in sorted(skills_dir.iterdir()):
        if not entry.is_dir():
            continue
        skill_md = entry / "SKILL.md"
        if not skill_md.exists():
            # Скиллы без SKILL.md не индексируются (но gaps() их покажет)
            continue
        try:
            skill_data = _build_skill_entry(entry)
            skills.append(skill_data)
        except Exception as e:
            print(f"[skill-indexer] Ошибка парсинга {entry.name}: {e}", file=sys.stderr)
            continue

    now = datetime.now(timezone.utc).isoformat()
    data = store.load()
    data["skills"] = skills
    data["total_skills"] = len(skills)
    data["last_full_reindex"] = now
    data["last_incremental"] = now
    store.save(data)

    return len(skills)


def incremental_update(skills_dir=None):
    """
    Инкрементальное обновление: проверяет mtime, обновляет только изменённые.

    Возвращает количество обновлённых скиллов.
    """
    skills_dir = Path(skills_dir or DEFAULT_SKILLS_DIR)
    if not skills_dir.exists():
        return 0

    data = store.load()
    # Ключ — имя папки (dir_name), извлекаем из path
    existing = {_dir_name_from_path(s["path"]): s for s in data.get("skills", [])}
    updated_count = 0

    # Множество текущих папок со SKILL.md
    current_names = set()
    for entry in sorted(skills_dir.iterdir()):
        if not entry.is_dir():
            continue
        skill_md = entry / "SKILL.md"
        if not skill_md.exists():
            continue

        current_names.add(entry.name)
        dir_mtime = _get_dir_mtime(entry)
        dir_mtime_iso = datetime.fromtimestamp(dir_mtime, tz=timezone.utc).isoformat()

        # Проверяем, изменился ли скилл
        if entry.name in existing:
            old_mtime = existing[entry.name].get("last_modified", "")
            if old_mtime == dir_mtime_iso:
                continue

        try:
            skill_data = _build_skill_entry(entry)
            existing[entry.name] = skill_data
            updated_count += 1
        except Exception as e:
            print(f"[skill-indexer] Ошибка парсинга {entry.name}: {e}", file=sys.stderr)
            continue

    # Удаляем скиллы, которых больше нет
    for name in list(existing.keys()):
        if name not in current_names:
            del existing[name]
            updated_count += 1

    now = datetime.now(timezone.utc).isoformat()
    skills_list = list(existing.values())
    data["skills"] = skills_list
    data["total_skills"] = len(skills_list)
    data["last_incremental"] = now
    store.save(data)

    return updated_count


def should_reindex():
    """
    Сравнивает текущее состояние папок с кэшем.

    Возвращает True если нужна переиндексация.
    """
    skills_dir = Path(DEFAULT_SKILLS_DIR)
    if not skills_dir.exists():
        return False

    data = store.load()
    if not data.get("last_full_reindex"):
        return True

    # Ключ — имя папки (dir_name), извлекаем из path
    existing = {_dir_name_from_path(s["path"]) for s in data.get("skills", [])}

    # Текущие папки со SKILL.md
    current = set()
    for entry in skills_dir.iterdir():
        if entry.is_dir() and (entry / "SKILL.md").exists():
            current.add(entry.name)

    # Появились новые или исчезли старые
    if current != existing:
        return True

    # Проверяем mtime
    skill_map = {_dir_name_from_path(s["path"]): s for s in data.get("skills", [])}
    for entry in skills_dir.iterdir():
        if not entry.is_dir() or not (entry / "SKILL.md").exists():
            continue
        dir_mtime = _get_dir_mtime(entry)
        dir_mtime_iso = datetime.fromtimestamp(dir_mtime, tz=timezone.utc).isoformat()
        old_mtime = skill_map.get(entry.name, {}).get("last_modified", "")
        if old_mtime != dir_mtime_iso:
            return True

    return False


def _parse_skill_md(path):
    """
    Парсит SKILL.md и извлекает метаданные.

    Возвращает dict: name, description, triggers, tools_required.
    """
    path = Path(path)
    try:
        content = path.read_text(encoding="utf-8")
    except OSError:
        return {"name": path.parent.name, "description": "", "triggers": [], "tools_required": []}

    name = path.parent.name
    description = ""
    triggers = []
    tools_required = []

    lines = content.split("\n")

    # name: из заголовка H1 или имени папки
    for line in lines:
        h1 = re.match(r"^#\s+(.+)$", line.strip())
        if h1:
            name = h1.group(1).strip()
            break

    # description: первый абзац после заголовка
    description = _extract_first_paragraph(lines)

    # triggers: секция "Триггер" / "Trigger" / "Вызов"
    triggers = _extract_section_items(content, r"(?:Триггер[ыи]?|Trigger[s]?|Вызов)")

    # tools_required: секция "Инструменты" / "Tools"
    tools_required = _extract_section_items(content, r"(?:Инструмент[ыа]?|Tool[s]?|Зависимости)")

    return {
        "name": name,
        "description": description,
        "triggers": triggers,
        "tools_required": tools_required,
    }


def _extract_first_paragraph(lines):
    """Извлекает первый абзац текста после первого заголовка H1."""
    found_h1 = False
    paragraph_lines = []

    for line in lines:
        stripped = line.strip()

        if not found_h1:
            if re.match(r"^#\s+", stripped):
                found_h1 = True
            continue

        # Пропускаем пустые строки сразу после заголовка
        if not paragraph_lines and not stripped:
            continue

        # Новый заголовок или пустая строка = конец абзаца
        if paragraph_lines and (not stripped or re.match(r"^#{1,6}\s+", stripped)):
            break

        # Пропускаем строки-разделители и метаданные
        if stripped.startswith("---") or stripped.startswith("```"):
            if paragraph_lines:
                break
            continue

        paragraph_lines.append(stripped)

    return " ".join(paragraph_lines).strip()


def _extract_section_items(content, section_pattern):
    """
    Извлекает элементы списка из секции с заданным паттерном заголовка.

    Ищет заголовок (##, ###) с паттерном, затем собирает элементы списка.
    Также ищет инлайн-формат: **Триггер**: `фраза1`, `фраза2`
    """
    items = []

    # Инлайн-формат: **Триггер**: `фраза1`, `фраза2` или жирный текст с двоеточием
    inline_pattern = rf"\*\*{section_pattern}\*\*\s*[:：]\s*(.+)"
    inline_match = re.search(inline_pattern, content, re.IGNORECASE)
    if inline_match:
        raw = inline_match.group(1)
        # Извлекаем из бэктиков
        backtick_items = re.findall(r"`([^`]+)`", raw)
        if backtick_items:
            items.extend(backtick_items)
        # Или из кавычек
        quoted_items = re.findall(r'["\u00ab]([^"\u00bb]+)["\u00bb]', raw)
        if quoted_items and not backtick_items:
            items.extend(quoted_items)

    # Секционный формат: ## Триггеры\n- фраза1\n- фраза2
    section_re = rf"^#{{1,3}}\s+{section_pattern}.*$"
    section_match = re.search(section_re, content, re.IGNORECASE | re.MULTILINE)
    if section_match:
        # Читаем строки после заголовка секции
        after = content[section_match.end():]
        for line in after.split("\n"):
            stripped = line.strip()
            if not stripped:
                continue
            # Новый заголовок = конец секции
            if re.match(r"^#{1,3}\s+", stripped):
                break
            # Элемент списка
            list_item = re.match(r"^[-*]\s+(.+)$", stripped)
            if list_item:
                item_text = list_item.group(1).strip()
                # Убираем бэктики и кавычки из элемента
                item_text = re.sub(r"^[`\"\u00ab]+|[`\"\u00bb]+$", "", item_text)
                # Убираем пояснения в скобках или после тире
                item_text = re.split(r"\s*[(\u2014\u2013—–]", item_text)[0].strip()
                if item_text:
                    items.append(item_text)

    return items


def _dir_name_from_path(path):
    """Извлекает имя папки из path вида '/skills/context-builder/'."""
    return path.strip("/").split("/")[-1]


def _compute_completeness(skill_dir):
    """
    Вычисляет полноту скилла.

    SKILL.md = 0.4, examples/ с файлами = 0.3, context/ с файлами = 0.2, scripts/ с файлами = 0.1
    """
    skill_dir = Path(skill_dir)
    result = {
        "has_skill_md": False,
        "has_examples": False,
        "has_context": False,
        "has_scripts": False,
        "score": 0.0,
    }

    score = 0.0

    if (skill_dir / "SKILL.md").exists():
        result["has_skill_md"] = True
        score += 0.4

    examples_dir = skill_dir / "examples"
    if examples_dir.is_dir() and any(examples_dir.iterdir()):
        result["has_examples"] = True
        score += 0.3

    context_dir = skill_dir / "context"
    if context_dir.is_dir() and any(context_dir.iterdir()):
        result["has_context"] = True
        score += 0.2

    scripts_dir = skill_dir / "scripts"
    if scripts_dir.is_dir() and any(scripts_dir.iterdir()):
        result["has_scripts"] = True
        score += 0.1

    result["score"] = round(score, 1)
    return result


def _count_files(directory):
    """Считает количество файлов в директории (рекурсивно)."""
    count = 0
    directory = Path(directory)
    for root, _dirs, files in os.walk(directory):
        count += len(files)
    return count


def _get_dir_mtime(directory):
    """Возвращает максимальный mtime среди всех файлов в директории."""
    directory = Path(directory)
    max_mtime = 0.0
    for root, _dirs, files in os.walk(directory):
        for f in files:
            fpath = Path(root) / f
            try:
                mtime = fpath.stat().st_mtime
                if mtime > max_mtime:
                    max_mtime = mtime
            except OSError:
                continue
    # Если файлов нет — mtime самой директории
    if max_mtime == 0.0:
        try:
            max_mtime = directory.stat().st_mtime
        except OSError:
            pass
    return max_mtime


def _build_skill_entry(skill_dir):
    """Собирает полную запись скилла для индекса."""
    skill_dir = Path(skill_dir)
    parsed = _parse_skill_md(skill_dir / "SKILL.md")
    completeness = _compute_completeness(skill_dir)
    file_count = _count_files(skill_dir)
    dir_mtime = _get_dir_mtime(skill_dir)
    last_modified = datetime.fromtimestamp(dir_mtime, tz=timezone.utc).isoformat()

    return {
        "name": parsed["name"],
        "path": f"/skills/{skill_dir.name}/",
        "description": parsed["description"],
        "triggers": parsed["triggers"],
        "tools_required": parsed["tools_required"],
        "completeness": completeness,
        "file_count": file_count,
        "last_modified": last_modified,
    }
