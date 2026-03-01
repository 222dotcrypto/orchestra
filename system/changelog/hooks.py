"""
Автоматические триггеры для changelog.

Парсинг результатов выполнения задач, определение категории,
генерация rollback-инструкций.
"""

import os
import re

from . import store, writer


def extract_category(task_description: str, changes: list) -> str:
    """
    Определяет категорию изменения.

    Приоритет:
    1. fix -- слова починил/фикс/ошибка/баг/краш
    2. config -- только конфиги/.env
    3. skill -- файлы в /skills/
    4. docs -- только .md файлы
    5. feature -- новые файлы + новая функциональность
    6. refactor -- только тесты или структура
    7. infrastructure -- остальное
    """
    combined = (task_description + " " + " ".join(changes)).lower()

    # fix
    fix_words = ["починил", "фикс", "ошибка", "баг", "краш", "fix", "bug", "crash", "исправ"]
    for w in fix_words:
        if w in combined:
            return "fix"

    # config
    config_patterns = [".env", "конфиг", "config", "настройк", "settings", ".yaml", ".yml", ".toml", ".ini"]
    if all(any(cp in c.lower() for cp in config_patterns) for c in changes if c.strip()):
        return "config"

    # skill
    if "/skills/" in combined or "skill" in combined or "скилл" in combined:
        return "skill"

    # docs
    if all(".md" in c.lower() for c in changes if c.strip()):
        return "docs"

    # feature
    new_words = ["создан", "добавлен", "новый", "new", "added", "created", "создал"]
    if any(w in combined for w in new_words):
        return "feature"

    # refactor
    refactor_words = ["рефактор", "refactor", "переименов", "перенёс", "restructur", "тест", "test"]
    for rw in refactor_words:
        if rw in combined:
            return "refactor"

    return "infrastructure"


def extract_context(agent_output: str) -> str:
    """
    Вытаскивает причину/контекст из текста агента.
    Первые 200 символов или ключевые предложения.
    """
    if not agent_output:
        return "не указан"

    text = agent_output.strip()

    # Ищем предложения с ключевыми словами причины
    reason_patterns = [
        r"(?:потому что|причина|чтобы|для того|необходимо|нужно было|решил|because|in order to|to fix|to add)[^.]*\.",
    ]

    for pattern in reason_patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            result = match.group(0).strip()
            if len(result) > 200:
                return result[:197] + "..."
            return result

    # Если ничего не нашли -- первые 200 символов
    if len(text) > 200:
        return text[:197] + "..."

    return text


def generate_rollback(changes: list, changed_files: list) -> str:
    """
    Генерирует инструкцию отката на основе изменений.
    """
    if not changes and not changed_files:
        return "Нет данных для генерации инструкции отката."

    instructions = []

    for change in changes:
        change_lower = change.lower()
        # Определяем имя файла
        parts = change.split(" — ", 1)
        if len(parts) < 2:
            parts = change.split(" - ", 1)

        filename = parts[0].strip() if parts else change.strip()

        if any(w in change_lower for w in ["создан", "добавлен", "created", "new", "создал"]):
            instructions.append(f"Удалить файл: {filename}")
        elif any(w in change_lower for w in ["удалён", "удалил", "deleted", "removed"]):
            instructions.append(f"Восстановить файл: {filename} (из git или бэкапа)")
        else:
            instructions.append(f"Откатить изменения в: {filename} (git checkout или ручной откат)")

    if not instructions:
        # Если не удалось разобрать changes, используем changed_files
        for f in changed_files:
            instructions.append(f"Откатить: {f}")

    return "; ".join(instructions)


def after_task(
    project_path: str,
    task_description: str,
    changed_files: list,
    agent_output: str = "",
) -> str:
    """
    Хук после выполнения задачи.
    Парсит результат, определяет категорию, записывает в changelog.

    Args:
        project_path: путь к проекту
        task_description: описание задачи
        changed_files: список изменённых файлов
        agent_output: вывод агента (опционально)

    Returns:
        ID записи (CHG-XXXX)
    """
    # Формируем changes из списка файлов
    changes = []
    for f in changed_files[:3]:
        changes.append(f"{f} — изменён")

    # Определяем категорию
    category = extract_category(task_description, changes)

    # Извлекаем контекст
    context = extract_context(agent_output)

    # Генерируем rollback
    rollback = generate_rollback(changes, changed_files)

    # Записываем через writer
    entry_id = writer.log_change(
        project_path=project_path,
        task=task_description,
        changes=changes,
        context=context,
        category=category,
    )

    # Дополняем запись rollback_notes через store напрямую
    # (writer уже записал, но rollback_notes был пустой)
    log = store.get_project_log(project_path, limit=1)
    if log and log[-1].get("id") == entry_id:
        log[-1]["rollback_notes"] = rollback
        # Перезаписать проектный лог с обновлённой записью
        full_log = store._read_log(os.path.join(project_path, "changelog.json"))
        if full_log and full_log[-1].get("id") == entry_id:
            full_log[-1]["rollback_notes"] = rollback
            store._atomic_write(os.path.join(project_path, "changelog.json"), full_log)

        # Обновить глобальный лог
        global_log = store._read_log(str(store.GLOBAL_LOG_PATH))
        if global_log and global_log[-1].get("id") == entry_id:
            global_log[-1]["rollback_notes"] = rollback
            store._atomic_write(str(store.GLOBAL_LOG_PATH), global_log)

    return entry_id
