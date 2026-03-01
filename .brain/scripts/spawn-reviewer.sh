#!/usr/bin/env bash
# spawn-reviewer.sh — Запуск ревьюера в отдельном tmux окне
# Использование: bash .brain/scripts/spawn-reviewer.sh <review-request-file>

set -euo pipefail

BRAIN_DIR=".brain"
TMUX_SESSION="orchestra"
REVIEW_REQUEST="${1:?Ошибка: укажи путь к review-request файлу}"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
WINDOW_NAME="reviewer"
LOG_FILE="${BRAIN_DIR}/logs/reviewer.log"

# --- Проверки ---

if [[ ! -f "$REVIEW_REQUEST" ]]; then
    echo "ОШИБКА: Review request не найден: ${REVIEW_REQUEST}"
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

# Убить старое окно reviewer если существует
if tmux list-windows -t "$TMUX_SESSION" -F '#{window_name}' 2>/dev/null | grep -q "^${WINDOW_NAME}$"; then
    echo "[${TIMESTAMP}] Окно ${WINDOW_NAME} уже существует. Убиваю старое." | tee -a "$LOG_FILE"
    tmux kill-window -t "${TMUX_SESSION}:${WINDOW_NAME}" 2>/dev/null || true
    sleep 1
fi

# --- Запуск через run-reviewer.sh (аналогично spawn-worker → run-worker) ---

WORK_DIR=$(pwd)
tmux new-window -t "$TMUX_SESSION" -n "$WINDOW_NAME"
tmux send-keys -t "${TMUX_SESSION}:${WINDOW_NAME}" \
    "cd '${WORK_DIR}' && bash .brain/scripts/run-reviewer.sh '${REVIEW_REQUEST}'" Enter

echo "[${TIMESTAMP}] Ревьюер запущен в ${TMUX_SESSION}:${WINDOW_NAME}"
echo "[${TIMESTAMP}] Review request: ${REVIEW_REQUEST}"
echo "[${TIMESTAMP}] Результат будет в .brain/review/results/"
