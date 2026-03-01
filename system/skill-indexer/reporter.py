"""
Отчёты и аналитика по индексу скиллов.

Каталог, анализ пробелов, статистика.
"""

from datetime import datetime
from pathlib import Path

from . import store
from .indexer import DEFAULT_SKILLS_DIR


def catalog():
    """
    Форматированный каталог скиллов.

    Формат:
    КАТАЛОГ СКИЛЛОВ (N скиллов, обновлено: DD.MM.YYYY HH:MM)

    Скилл               | Описание                        | Полнота
    ─────────────────────|─────────────────────────────────|────────
    token-research       | Автоанализ токена               | ████░ 80%
    """
    data = store.load()
    skills = data.get("skills", [])
    total = data.get("total_skills", len(skills))

    # Дата последнего обновления
    last_reindex = data.get("last_full_reindex") or data.get("last_incremental")
    if last_reindex:
        try:
            dt = datetime.fromisoformat(last_reindex)
            date_str = dt.strftime("%d.%m.%Y %H:%M")
        except ValueError:
            date_str = last_reindex
    else:
        date_str = "никогда"

    lines = []
    lines.append(f"КАТАЛОГ СКИЛЛОВ ({total} скиллов, обновлено: {date_str})")
    lines.append("")

    if not skills:
        lines.append("(пусто)")
        return "\n".join(lines)

    # Вычисляем ширину колонок
    name_width = max(len("Скилл"), max(len(s["name"]) for s in skills))
    desc_width = max(len("Описание"), 30)

    # Заголовок
    header = (
        f"{'Скилл':<{name_width}} | "
        f"{'Описание':<{desc_width}} | "
        f"Полнота"
    )
    lines.append(header)

    separator = (
        f"{'─' * name_width}─┼─"
        f"{'─' * desc_width}─┼─"
        f"{'─' * 10}"
    )
    lines.append(separator)

    # Строки
    for skill in sorted(skills, key=lambda s: s["name"]):
        name = skill["name"]
        desc = skill.get("description", "")
        # Обрезаем описание
        if len(desc) > desc_width:
            desc = desc[:desc_width - 3] + "..."

        score = skill.get("completeness", {}).get("score", 0)
        bar = _progress_bar(score)

        row = (
            f"{name:<{name_width}} | "
            f"{desc:<{desc_width}} | "
            f"{bar}"
        )
        lines.append(row)

    return "\n".join(lines)


def gaps():
    """
    Анализ пробелов: папки в skills/ без SKILL.md.

    Возвращает строку с отчётом.
    """
    skills_dir = Path(DEFAULT_SKILLS_DIR)
    if not skills_dir.exists():
        return "Директория skills/ не найдена."

    missing = []
    for entry in sorted(skills_dir.iterdir()):
        if entry.is_dir() and not (entry / "SKILL.md").exists():
            missing.append(entry.name)

    if not missing:
        return "Все папки в skills/ содержат SKILL.md. Пробелов нет."

    lines = [f"ПРОБЕЛЫ: {len(missing)} папок без SKILL.md", ""]
    for name in missing:
        lines.append(f"  - {name}/")

    return "\n".join(lines)


def stats():
    """
    Статистика индекса.

    Возвращает dict:
    - total_skills: количество проиндексированных скиллов
    - average_completeness: средняя полнота (0.0 .. 1.0)
    - last_reindex: ISO timestamp последней полной переиндексации
    - skills_without_md: количество папок без SKILL.md
    """
    data = store.load()
    skills = data.get("skills", [])

    # Средняя полнота
    if skills:
        total_score = sum(s.get("completeness", {}).get("score", 0) for s in skills)
        avg = round(total_score / len(skills), 2)
    else:
        avg = 0.0

    # Папки без SKILL.md
    skills_dir = Path(DEFAULT_SKILLS_DIR)
    without_md = 0
    if skills_dir.exists():
        for entry in skills_dir.iterdir():
            if entry.is_dir() and not (entry / "SKILL.md").exists():
                without_md += 1

    return {
        "total_skills": data.get("total_skills", len(skills)),
        "average_completeness": avg,
        "last_reindex": data.get("last_full_reindex"),
        "skills_without_md": without_md,
    }


def _progress_bar(score, width=5):
    """
    Генерирует прогресс-бар.

    score 0.0..1.0 -> ████░ 80%
    """
    filled = round(score * width)
    empty = width - filled
    bar = "\u2588" * filled + "\u2591" * empty
    percent = round(score * 100)
    return f"{bar} {percent:>3}%"
