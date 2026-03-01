"""
Запись изменений в changelog.

Основная точка входа: log_change().
"""

import os
from datetime import datetime, timezone

from . import store


# Ключевые слова для автоопределения категории
_CATEGORY_KEYWORDS = {
    "fix": ["починил", "фикс", "ошибка", "баг", "краш", "fix", "bug", "crash", "исправ"],
    "config": [".env", "конфиг", "config", "настройк", "settings"],
    "docs": [".md", "документ", "readme", "docs"],
    "skill": ["skill", "скилл", "навык"],
}

VALID_CATEGORIES = {"feature", "fix", "refactor", "config", "skill", "docs", "infrastructure"}


def _detect_category(task: str, changes: list) -> str:
    """Автоопределение категории по задаче и списку изменений."""
    combined = (task + " " + " ".join(changes)).lower()

    # fix — приоритетная проверка
    for kw in _CATEGORY_KEYWORDS["fix"]:
        if kw in combined:
            return "fix"

    # config
    for kw in _CATEGORY_KEYWORDS["config"]:
        if kw in combined:
            return "config"

    # skill
    for kw in _CATEGORY_KEYWORDS["skill"]:
        if kw in combined:
            return "skill"

    # docs
    for kw in _CATEGORY_KEYWORDS["docs"]:
        if kw in combined:
            return "docs"

    # Новые файлы -> feature
    has_new = any("создан" in c.lower() or "добавлен" in c.lower() or "new" in c.lower()
                  or "создал" in c.lower() or "added" in c.lower()
                  for c in changes)
    if has_new:
        return "feature"

    # Только тесты или рефакторинг
    refactor_words = ["рефактор", "refactor", "переименов", "перенёс", "restructur", "тест", "test"]
    for rw in refactor_words:
        if rw in combined:
            return "refactor"

    return "infrastructure"


def _make_summary(task: str) -> str:
    """Генерация краткого summary из описания задачи."""
    task = task.strip()

    # Берём первое предложение
    for sep in [". ", ".\n", "\n"]:
        if sep in task:
            task = task[:task.index(sep)]
            break

    # Ограничиваем длину
    if len(task) > 120:
        task = task[:117] + "..."

    return task


def _extract_files(changes: list) -> tuple:
    """Извлечь имена файлов из списка changes. Возвращает (changed, created, deleted)."""
    changed = []
    created = []
    deleted = []

    for item in changes:
        # Формат: "file.py -- что сделано"
        parts = item.split(" — ", 1)
        if len(parts) < 2:
            parts = item.split(" - ", 1)

        if not parts:
            continue

        filename = parts[0].strip()

        if len(parts) > 1:
            action = parts[1].lower()
            if any(w in action for w in ["создан", "добавлен", "created", "new", "создал"]):
                created.append(filename)
            elif any(w in action for w in ["удалён", "удалил", "deleted", "removed"]):
                deleted.append(filename)
            else:
                changed.append(filename)
        else:
            changed.append(filename)

    return changed, created, deleted


def log_change(
    project_path: str,
    task: str,
    changes: list,
    context: str = "",
    category: str = None,
) -> str:
    """
    Записать изменение в changelog.

    Args:
        project_path: путь к корню проекта
        task: описание задачи
        changes: список изменений ["file.py -- что сделано", ...]
        context: почему сделано это изменение
        category: категория (auto-detect если None)

    Returns:
        ID записи (CHG-XXXX)
    """
    # Ограничение: максимум 3 пункта в changes
    truncated_changes = changes[:3]

    # Автоопределение категории
    if category is None or category not in VALID_CATEGORIES:
        category = _detect_category(task, truncated_changes)

    # Извлечение файлов
    files_changed, files_created, files_deleted = _extract_files(truncated_changes)

    # Формирование записи
    entry = {
        "id": "",  # будет заполнено в store.append()
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "project": os.path.basename(os.path.normpath(project_path)),
        "task": task,
        "category": category,
        "summary": _make_summary(task),
        "changes": truncated_changes,
        "decision_context": context if context else "не указан",
        "files_changed": files_changed,
        "files_created": files_created,
        "files_deleted": files_deleted,
        "rollback_notes": "",
    }

    entry_id = store.append(project_path, entry)
    return entry_id
