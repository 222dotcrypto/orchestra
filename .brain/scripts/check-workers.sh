#!/usr/bin/env bash
# check-workers.sh — Проверка здоровья воркеров через tmux/ps (замена heartbeat)
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

    # Проверяем сигнальные файлы
    CURRENT_TASK=$(jq -r '.current_task // ""' "$wf" 2>/dev/null)
    HAS_SIGNAL="false"
    if [[ -n "$CURRENT_TASK" ]]; then
        if [[ -f "${BRAIN_DIR}/signals/${CURRENT_TASK}.review" ]]; then
            HAS_SIGNAL="true"
        fi
    fi

    if [[ "$first" == "true" ]]; then
        first=false
    else
        echo ","
    fi

    echo "  \"${WID}\": {\"window\": ${WINDOW_ALIVE}, \"process\": ${PROCESS_ALIVE}, \"signal\": ${HAS_SIGNAL}}"
done

echo ""
echo "}"
