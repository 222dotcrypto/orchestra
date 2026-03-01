#!/usr/bin/env bash
# check-workers.sh — Проверка здоровья воркеров через tmux/ps
# Использование: bash .brain/scripts/check-workers.sh
# Возвращает JSON с состоянием каждого воркера.

set -euo pipefail

BRAIN_DIR=".brain"
TMUX_SESSION="orchestra"

echo "{"
first=true

for wf in "${BRAIN_DIR}"/workers/worker-*.json; do
    [[ -f "$wf" ]] || continue

    WID=$(basename "$wf" .json)

    # Проверяем tmux окно
    if tmux list-windows -t "$TMUX_SESSION" -F '#{window_name}' 2>/dev/null | grep -q "^${WID}$"; then
        WINDOW_ALIVE="true"
        # Получаем PID процесса в pane
        PANE_PID=$(tmux list-panes -t "${TMUX_SESSION}:${WID}" -F '#{pane_pid}' 2>/dev/null | head -1)
        if [[ -n "$PANE_PID" ]] && ps -p "$PANE_PID" > /dev/null 2>&1; then
            PROCESS_ALIVE="true"
        else
            PROCESS_ALIVE="false"
        fi
    else
        WINDOW_ALIVE="false"
        PROCESS_ALIVE="false"
    fi

    # Проверяем сигнальные файлы (.done или .failed)
    CURRENT_TASK=$(jq -r '.current_task // ""' "$wf" 2>/dev/null)
    SIGNAL_TYPE="none"
    if [[ -n "$CURRENT_TASK" ]]; then
        if [[ -f "${BRAIN_DIR}/signals/${CURRENT_TASK}.done" ]]; then
            SIGNAL_TYPE="done"
        elif [[ -f "${BRAIN_DIR}/signals/${CURRENT_TASK}.failed" ]]; then
            SIGNAL_TYPE="failed"
        fi
    fi

    if [[ "$first" == "true" ]]; then
        first=false
    else
        echo ","
    fi

    echo "  \"${WID}\": {\"window\": ${WINDOW_ALIVE}, \"process\": ${PROCESS_ALIVE}, \"signal_type\": \"${SIGNAL_TYPE}\"}"
done

echo ""
echo "}"
