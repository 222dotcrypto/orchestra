#!/usr/bin/env bash
# run-reviewer.sh — Runner для ревьюера. Вызывается из tmux окна.
# Использование: bash .brain/scripts/run-reviewer.sh <review-request-file>

set -euo pipefail

BRAIN_DIR=".brain"
REVIEW_REQUEST="${1:?Ошибка: укажи путь к review-request файлу}"
LOG_FILE="${BRAIN_DIR}/logs/reviewer.log"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
RESULT_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RESULT_FILE="${BRAIN_DIR}/review/results/review-${RESULT_TIMESTAMP}.md"

if [[ ! -f "$REVIEW_REQUEST" ]]; then
    echo "[${TIMESTAMP}] ОШИБКА: Review request не найден: ${REVIEW_REQUEST}" | tee -a "$LOG_FILE"
    exit 1
fi

echo "[${TIMESTAMP}] Запуск ревьюера" | tee -a "$LOG_FILE"
echo "[${TIMESTAMP}] Review request: ${REVIEW_REQUEST}" | tee -a "$LOG_FILE"
echo "[${TIMESTAMP}] Результат будет в: ${RESULT_FILE}" | tee -a "$LOG_FILE"

# Читаем system prompt из шаблона
SYSTEM_PROMPT=$(cat "${BRAIN_DIR}/prompts/templates/reviewer.md")

# Задача для ревьюера
INITIAL_TASK="Ты ревьюер. Прочитай review-request: ${REVIEW_REQUEST}. Проверь все файлы из него по критериям из system prompt. Запиши результат в ${RESULT_FILE}. После записи результата — заверши сессию."

# Разрешаем запуск внутри другой сессии Claude Code
unset CLAUDECODE

# Запуск claude
exec claude \
    --dangerously-skip-permissions \
    --system-prompt "$SYSTEM_PROMPT" \
    -p "$INITIAL_TASK" \
    2>&1 | tee -a "$LOG_FILE"
