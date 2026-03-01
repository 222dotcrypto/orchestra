"""
Хранилище changelog-записей.

Два уровня: проектный лог ({project_root}/changelog.json) и глобальный лог.
Атомарная запись через /tmp -> mv.
"""

import json
import os
import shutil
import tempfile
from pathlib import Path

GLOBAL_LOG_PATH = Path(__file__).parent / "global.json"


def _read_log(path: str) -> list:
    """Прочитать лог из файла. Возвращает пустой список при ошибке."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
            if isinstance(data, list):
                return data
    except (FileNotFoundError, json.JSONDecodeError):
        pass
    return []


def _atomic_write(path: str, data: list) -> None:
    """Атомарная запись: write -> /tmp -> mv."""
    import sys

    try:
        dir_path = os.path.dirname(path)
        os.makedirs(dir_path, exist_ok=True)

        fd, tmp_path = tempfile.mkstemp(suffix=".json", prefix="changelog_")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            shutil.move(tmp_path, path)
        except Exception:
            # Удаляем временный файл при ошибке
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
            raise
    except Exception as e:
        print(f"[changelog] ошибка записи в {path}: {e}", file=sys.stderr)


def _next_id(project_log: list) -> str:
    """Определить следующий ID (CHG-XXXX) на основе последней записи."""
    if not project_log:
        return "CHG-0001"

    last_entry = project_log[-1]
    last_id = last_entry.get("id", "CHG-0000")
    try:
        num = int(last_id.split("-")[1])
    except (IndexError, ValueError):
        num = 0

    return f"CHG-{num + 1:04d}"


def append(project_path: str, entry: dict) -> str:
    """
    Добавить запись в проектный и глобальный логи.
    Возвращает присвоенный ID.
    """
    project_log_path = os.path.join(project_path, "changelog.json")
    project_log = _read_log(project_log_path)

    # Присвоить ID
    entry_id = _next_id(project_log)
    entry["id"] = entry_id

    # Записать в проектный лог
    project_log.append(entry)
    _atomic_write(project_log_path, project_log)

    # Записать в глобальный лог
    global_log = _read_log(str(GLOBAL_LOG_PATH))
    global_log.append(entry)
    _atomic_write(str(GLOBAL_LOG_PATH), global_log)

    return entry_id


def get_project_log(project_path: str, limit: int = 50) -> list:
    """Последние N записей проектного лога."""
    log_path = os.path.join(project_path, "changelog.json")
    entries = _read_log(log_path)
    return entries[-limit:]


def get_global_log(limit: int = 100) -> list:
    """Последние N записей глобального лога."""
    entries = _read_log(str(GLOBAL_LOG_PATH))
    return entries[-limit:]


def is_duplicate(project_path: str, task: str) -> bool:
    """Проверка: есть ли запись с таким task в последних 10 записях проекта."""
    entries = get_project_log(project_path, limit=10)
    task_lower = task.lower().strip()
    for entry in entries:
        if entry.get("task", "").lower().strip() == task_lower:
            return True
    return False
