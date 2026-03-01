#!/usr/bin/env bash
# run-worker.sh — Runner для воркера. Вызывается из tmux окна.
# Использование: bash .brain/scripts/run-worker.sh <worker-id> <role>
#
# Читает промпт из файла и передаёт claude через -p.
# Решает проблему экранирования спецсимволов в промптах.

set -euo pipefail

WORKER_ID="${1:?Ошибка: укажи worker-id}"
ROLE="${2:?Ошибка: укажи роль}"
BRAIN_DIR=".brain"
PROMPT_FILE="${BRAIN_DIR}/prompts/${WORKER_ID}.md"
LOG_FILE="${BRAIN_DIR}/logs/${WORKER_ID}.log"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "[${TIMESTAMP}] ОШИБКА: Промпт не найден: ${PROMPT_FILE}" | tee -a "$LOG_FILE"
    exit 1
fi

echo "[${TIMESTAMP}] Запуск воркера ${WORKER_ID} (${ROLE})" | tee -a "$LOG_FILE"

# Читаем промпт из файла — без экранирования, без потери форматирования
SYSTEM_PROMPT=$(cat "$PROMPT_FILE")

# Начальная задача — минимальная, всё остальное в system prompt
INITIAL_TASK="Ты воркер ${WORKER_ID} (${ROLE}). Прочитай .brain/WORKER_PROTOCOL.md и найди свою задачу в .brain/tasks/ (assigned_to=\"${WORKER_ID}\", status=\"assigned\"). Выполни задачу. Меняй ТОЛЬКО файлы из owned_files."

# Разрешаем запуск внутри другой сессии Claude Code
unset CLAUDECODE

# Запуск claude с полными правами (воркер изолирован через owned_files)
exec claude \
    --dangerously-skip-permissions \
    --system-prompt "$SYSTEM_PROMPT" \
    -p "$INITIAL_TASK" \
    2>&1 | tee -a "$LOG_FILE"
