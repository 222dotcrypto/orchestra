"""
Подбор скилла под задачу.

Локальный поиск без API. Токенизация + сравнение по триггерам и описаниям.
"""

import re
from . import store


def find_skill(task_description):
    """
    Находит топ-3 подходящих скилла для задачи.

    Алгоритм:
    1. Точное совпадение по триггерам
    2. Токенизация task_description, поиск совпадений по description + triggers
    3. Scoring: точное = high, частичное = medium, нечёткое = low

    Возвращает list of dict:
    [{"name": "...", "path": "...", "confidence": "high|medium|low", "match_reason": "..."}]
    """
    data = store.load()
    skills = data.get("skills", [])
    if not skills:
        return []

    task_lower = task_description.lower().strip()
    candidates = []

    for skill in skills:
        score, reason = _score_skill(skill, task_lower)
        if score > 0:
            candidates.append({
                "name": skill["name"],
                "path": skill["path"],
                "confidence": _score_to_confidence(score),
                "match_reason": reason,
                "_score": score,
            })

    # Сортируем по убыванию score, берём топ-3
    candidates.sort(key=lambda x: x["_score"], reverse=True)
    top = candidates[:3]

    # Убираем внутреннее поле _score
    for c in top:
        del c["_score"]

    return top


def exact_match(trigger_phrase):
    """
    Точное совпадение по триггерам (case-insensitive).

    Возвращает dict скилла или None.
    """
    data = store.load()
    phrase_lower = trigger_phrase.lower().strip()

    for skill in data.get("skills", []):
        for trigger in skill.get("triggers", []):
            if trigger.lower().strip() == phrase_lower:
                return skill

    return None


def get_skill(name):
    """Обёртка над store.get_skill()."""
    return store.get_skill(name)


def _score_skill(skill, task_lower):
    """
    Оценивает релевантность скилла для задачи.

    Возвращает (score: float, reason: str).
    Score: 0 = нет совпадения, 1.0 = точное совпадение триггера.
    """
    best_score = 0.0
    best_reason = ""

    # 1. Точное совпадение триггера
    for trigger in skill.get("triggers", []):
        trigger_lower = trigger.lower().strip()
        if trigger_lower in task_lower or task_lower in trigger_lower:
            if trigger_lower == task_lower:
                return 1.0, f"Точное совпадение триггера: \"{trigger}\""
            best_score = max(best_score, 0.9)
            best_reason = f"Триггер содержится в задаче: \"{trigger}\""

    # 2. Токенизация и поиск по триггерам
    task_tokens = _tokenize(task_lower)
    if not task_tokens:
        return best_score, best_reason

    for trigger in skill.get("triggers", []):
        trigger_tokens = _tokenize(trigger.lower())
        if not trigger_tokens:
            continue
        overlap = task_tokens & trigger_tokens
        if overlap:
            ratio = len(overlap) / len(trigger_tokens)
            score = 0.5 + ratio * 0.3  # 0.5 .. 0.8
            if score > best_score:
                best_score = score
                best_reason = f"Совпадение токенов триггера ({len(overlap)}/{len(trigger_tokens)}): {', '.join(sorted(overlap))}"

    # 3. Поиск по описанию
    description = skill.get("description", "").lower()
    if description:
        desc_tokens = _tokenize(description)
        overlap = task_tokens & desc_tokens
        if overlap:
            # Нормируем по количеству токенов задачи
            ratio = len(overlap) / len(task_tokens)
            score = 0.2 + ratio * 0.3  # 0.2 .. 0.5
            if score > best_score:
                best_score = score
                best_reason = f"Совпадение с описанием ({len(overlap)} токенов): {', '.join(sorted(overlap))}"

    # 4. Совпадение по имени скилла
    name_tokens = _tokenize(skill.get("name", "").lower().replace("-", " "))
    if name_tokens:
        overlap = task_tokens & name_tokens
        if overlap:
            ratio = len(overlap) / len(name_tokens)
            score = 0.4 + ratio * 0.4  # 0.4 .. 0.8
            if score > best_score:
                best_score = score
                best_reason = f"Совпадение с именем скилла: {', '.join(sorted(overlap))}"

    # Отсечка: ниже low не возвращаем
    if best_score < 0.2:
        return 0, ""

    return best_score, best_reason


def _score_to_confidence(score):
    """Преобразует числовой score в уровень confidence."""
    if score >= 0.8:
        return "high"
    elif score >= 0.4:
        return "medium"
    else:
        return "low"


# Стоп-слова для токенизации (русские и английские)
_STOP_WORDS = frozenset({
    # Русские
    "и", "в", "на", "с", "по", "для", "из", "к", "от", "до", "за", "о", "об",
    "не", "но", "а", "что", "как", "это", "все", "уже", "ещё", "еще", "или",
    "мне", "мой", "мою", "его", "её", "их", "нам", "вам", "нас", "вас",
    "быть", "есть", "был", "была", "были", "будет", "будут",
    "этот", "эта", "эти", "тот", "та", "те", "то",
    # Английские
    "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
    "in", "on", "at", "to", "for", "of", "with", "by", "from", "as",
    "and", "or", "but", "not", "no", "if", "it", "its", "this", "that",
    "do", "does", "did", "will", "would", "can", "could", "should",
    "i", "you", "he", "she", "we", "they", "me", "my", "your",
})


def _tokenize(text):
    """
    Разбивает текст на значимые токены.

    Убирает стоп-слова и токены короче 2 символов.
    """
    # Разделяем по не-буквенным символам (поддержка кириллицы)
    tokens = re.findall(r"[a-zA-Z\u0400-\u04ff]{2,}", text.lower())
    return {t for t in tokens if t not in _STOP_WORDS}
