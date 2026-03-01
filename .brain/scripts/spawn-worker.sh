#!/usr/bin/env bash
# spawn-worker.sh — Запуск воркера в tmux окне
# Использование: bash .brain/scripts/spawn-worker.sh <worker-id> <role>

set -euo pipefail

BRAIN_DIR=".brain"
TMUX_SESSION="orchestra"
WORKER_ID="${1:?Ошибка: укажи worker-id (например: worker-01)}"
ROLE="${2:?Ошибка: укажи роль (например: coder, tester, researcher)}"
PROMPT_FILE="${BRAIN_DIR}/prompts/${WORKER_ID}.md"
WORKER_FILE="${BRAIN_DIR}/workers/${WORKER_ID}.json"
LOG_FILE="${BRAIN_DIR}/logs/${WORKER_ID}.log"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# --- Проверки ---

if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "ОШИБКА: Промпт не найден: ${PROMPT_FILE}"
    echo "Сначала сгенерируй промпт для воркера."
    exit 1
fi

if ! command -v tmux &> /dev/null; then
    echo "ОШИБКА: tmux не установлен. Установи: brew install tmux"
    exit 1
fi

if ! command -v claude &> /dev/null; then
    echo "ОШИБКА: claude не установлен."
    exit 1
fi

# --- Подготовка tmux ---

# Создать сессию если не существует
if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    tmux new-session -d -s "$TMUX_SESSION" -n "brain"
    echo "[${TIMESTAMP}] Создана tmux сессия: ${TMUX_SESSION}"
fi

# Убить старое окно если существует
if tmux list-windows -t "$TMUX_SESSION" -F '#{window_name}' 2>/dev/null | grep -q "^${WORKER_ID}$"; then
    echo "ПРЕДУПРЕЖДЕНИЕ: Окно ${WORKER_ID} уже существует. Убиваю старое."
    tmux kill-window -t "${TMUX_SESSION}:${WORKER_ID}" 2>/dev/null || true
    sleep 1
fi

# --- Запуск воркера ---

# Создаём tmux окно и запускаем run-worker.sh
# Вся логика чтения промпта и запуска claude — внутри run-worker.sh
# Это решает проблему экранирования спецсимволов в промптах
WORK_DIR=$(pwd)
tmux new-window -t "$TMUX_SESSION" -n "$WORKER_ID"
tmux send-keys -t "${TMUX_SESSION}:${WORKER_ID}" \
    "cd '${WORK_DIR}' && bash .brain/scripts/run-worker.sh '${WORKER_ID}' '${ROLE}'" Enter

# --- Регистрация воркера ---

sleep 2
PANE_PID=$(tmux list-panes -t "${TMUX_SESSION}:${WORKER_ID}" -F '#{pane_pid}' 2>/dev/null | head -1)

# Атомарная запись: /tmp → mv
cat > "/tmp/${WORKER_ID}.tmp" << EOF
{
  "id": "${WORKER_ID}",
  "role": "${ROLE}",
  "status": "idle",
  "current_task": null,
  "tmux_window": "${TMUX_SESSION}:${WORKER_ID}",
  "pid": ${PANE_PID:-null},
  "started_at": "${TIMESTAMP}",
  "last_heartbeat": "${TIMESTAMP}"
}
EOF
mv "/tmp/${WORKER_ID}.tmp" "$WORKER_FILE"

echo "[${TIMESTAMP}] Воркер ${WORKER_ID} (${ROLE}) запущен в ${TMUX_SESSION}:${WORKER_ID}"
echo "[${TIMESTAMP}] Промпт: ${PROMPT_FILE}"
echo "[${TIMESTAMP}] Статус: ${WORKER_FILE}"
