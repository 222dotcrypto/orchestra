"""
Чтение, поиск и отчёты по changelog.
"""

import os
from collections import defaultdict
from datetime import datetime, timedelta, timezone

from . import store


def _parse_timestamp(ts: str) -> datetime:
    """Парсинг ISO 8601 timestamp."""
    try:
        return datetime.fromisoformat(ts)
    except (ValueError, TypeError):
        return datetime.min.replace(tzinfo=timezone.utc)


def _format_entry(entry: dict) -> str:
    """Форматирование одной записи для вывода."""
    ts = _parse_timestamp(entry.get("timestamp", ""))
    ts_str = ts.strftime("%d.%m %H:%M") if ts != datetime.min.replace(tzinfo=timezone.utc) else "??:??"

    entry_id = entry.get("id", "???")
    category = entry.get("category", "???")
    summary = entry.get("summary", "")
    changes = entry.get("changes", [])
    context = entry.get("decision_context", "")

    lines = [f"[{entry_id}] {ts_str} | {category}"]
    lines.append(summary)

    if changes:
        files_str = ", ".join(changes[:3])
        lines.append(f"  -> {files_str}")

    if context and context != "не указан":
        lines.append(f"  Почему: {context}")

    return "\n".join(lines)


def history(project_path: str, limit: int = 10) -> str:
    """
    Форматированный текст последних N изменений проекта.
    """
    entries = store.get_project_log(project_path, limit=limit)
    project_name = os.path.basename(os.path.normpath(project_path))

    if not entries:
        return f"CHANGELOG -- {project_name}\n{'=' * 30}\n\nЗаписей нет."

    header = f"CHANGELOG -- {project_name}\n{'=' * 30}\n"

    formatted = []
    for entry in reversed(entries):
        formatted.append(_format_entry(entry))

    return header + "\n\n".join(formatted)


def search(query: str, project_path: str = None) -> list:
    """
    Поиск по task, summary, changes, decision_context.
    Если project_path указан -- ищет в проекте, иначе в глобальном логе.
    """
    if project_path:
        entries = store.get_project_log(project_path, limit=9999)
    else:
        entries = store.get_global_log(limit=9999)

    query_lower = query.lower()
    results = []

    for entry in entries:
        searchable = " ".join([
            entry.get("task", ""),
            entry.get("summary", ""),
            " ".join(entry.get("changes", [])),
            entry.get("decision_context", ""),
        ]).lower()

        if query_lower in searchable:
            results.append(entry)

    return results


def report(period: str = "week") -> str:
    """
    Сводка за период (week/month).
    Группировка по проектам, подсчёт по категориям.
    """
    now = datetime.now(timezone.utc)

    if period == "month":
        cutoff = now - timedelta(days=30)
        period_label = "месяц"
    else:
        cutoff = now - timedelta(days=7)
        period_label = "неделю"

    entries = store.get_global_log(limit=9999)

    # Фильтрация по периоду
    filtered = []
    for entry in entries:
        ts = _parse_timestamp(entry.get("timestamp", ""))
        if ts >= cutoff:
            filtered.append(entry)

    if not filtered:
        return f"За последнюю {period_label} изменений нет."

    # Группировка по проектам
    by_project = defaultdict(list)
    for entry in filtered:
        project = entry.get("project", "unknown")
        by_project[project].append(entry)

    # Подсчёт по категориям
    by_category = defaultdict(int)
    for entry in filtered:
        cat = entry.get("category", "other")
        by_category[cat] += 1

    # Форматирование
    lines = [f"ОТЧЁТ за {period_label} ({len(filtered)} изменений)", "=" * 40, ""]

    lines.append("По проектам:")
    for project, proj_entries in sorted(by_project.items()):
        lines.append(f"  {project}: {len(proj_entries)} изменений")

    lines.append("")
    lines.append("По категориям:")
    for cat, count in sorted(by_category.items(), key=lambda x: -x[1]):
        lines.append(f"  {cat}: {count}")

    return "\n".join(lines)


def context_restore(project_path: str) -> str:
    """
    Последние 5-10 изменений + текущее состояние для возврата к проекту.
    """
    entries = store.get_project_log(project_path, limit=10)
    project_name = os.path.basename(os.path.normpath(project_path))

    if not entries:
        return f"Проект {project_name}: история изменений пуста."

    lines = [
        f"КОНТЕКСТ ПРОЕКТА: {project_name}",
        "=" * 40,
        "",
        f"Всего записей: {len(entries)} (последние)",
        "",
    ]

    # Последние категории
    categories = [e.get("category", "?") for e in entries]
    lines.append(f"Направления работы: {', '.join(set(categories))}")
    lines.append("")

    # Последние изменения
    lines.append("Последние изменения:")
    for entry in reversed(entries[-5:]):
        entry_id = entry.get("id", "???")
        summary = entry.get("summary", "")
        category = entry.get("category", "?")
        lines.append(f"  [{entry_id}] {category}: {summary}")

    # Текущие файлы в работе
    recent_files = set()
    for entry in entries[-5:]:
        for f in entry.get("files_changed", []):
            recent_files.add(f)
        for f in entry.get("files_created", []):
            recent_files.add(f)

    if recent_files:
        lines.append("")
        lines.append("Файлы в работе (недавние):")
        for f in sorted(recent_files):
            lines.append(f"  {f}")

    return "\n".join(lines)
