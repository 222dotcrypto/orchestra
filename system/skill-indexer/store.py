"""
Хранилище индекса скиллов.

Атомарная запись: write -> /tmp -> mv в целевой путь.
"""

import json
import os
import shutil
import tempfile
from pathlib import Path

INDEX_PATH = Path(__file__).parent / "index.json"


def _empty_index():
    """Пустая структура индекса."""
    return {
        "version": 1,
        "last_full_reindex": None,
        "last_incremental": None,
        "total_skills": 0,
        "skills": [],
    }


def load():
    """Читает index.json, возвращает dict. Если файла нет — пустая структура."""
    if not INDEX_PATH.exists():
        return _empty_index()
    try:
        with open(INDEX_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return _empty_index()


def save(data):
    """Атомарная запись index.json (write -> /tmp -> mv)."""
    INDEX_PATH.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix="skill-index-", suffix=".json", dir="/tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        shutil.move(tmp_path, str(INDEX_PATH))
    except Exception:
        # Очистка временного файла при ошибке
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise


def get_skill(name):
    """Возвращает dict скилла по имени или None."""
    data = load()
    for skill in data.get("skills", []):
        if skill.get("name") == name:
            return skill
    return None
