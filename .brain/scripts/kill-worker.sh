#!/usr/bin/env bash
# kill-worker.sh — Остановка воркера
# Использование: bash .brain/scripts/kill-worker.sh <worker-id>
#                bash .brain/scripts/kill-worker.sh --all

set -euo pipefail

BRAIN_DIR=".brain"
TMUX_SESSION="orchestra"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

kill_worker() {
    local worker_id="$1"
    local worker_file="${BRAIN_DIR}/workers/${worker_id}.json"

    # Убить tmux окно
    if tmux list-windows -t "$TMUX_SESSION" -F '#{window_name}' 2>/dev/null | grep -q "^${worker_id}$"; then
        tmux kill-window -t "${TMUX_SESSION}:${worker_id}" 2>/dev/null || true
        echo "[${TIMESTAMP}] Убито tmux окно: ${TMUX_SESSION}:${worker_id}"
    else
        echo "[${TIMESTAMP}] Окно ${worker_id} не найдено в tmux"
    fi

    # Обновить статус воркера
    if [[ -f "$worker_file" ]]; then
        if command -v jq &> /dev/null; then
            jq --arg ts "$TIMESTAMP" '.status = "dead" | .current_task = null | .last_heartbeat = $ts' \
                "$worker_file" > "/tmp/${worker_id}.tmp" && mv "/tmp/${worker_id}.tmp" "$worker_file"
        else
            # Fallback без jq
            sed -i.bak 's/"status": "[^"]*"/"status": "dead"/' "$worker_file"
            rm -f "${worker_file}.bak"
        fi
        echo "[${TIMESTAMP}] Статус ${worker_id} обновлён на 'dead'"
    else
        echo "[${TIMESTAMP}] Файл воркера не найден: ${worker_file}"
    fi
}

# Обработка аргументов
if [[ "${1:?Ошибка: укажи worker-id или --all}" == "--all" ]]; then
    echo "[${TIMESTAMP}] Убиваю всех воркеров..."
    for worker_file in "${BRAIN_DIR}"/workers/worker-*.json; do
        [[ -f "$worker_file" ]] || continue
        worker_id=$(basename "$worker_file" .json)
        kill_worker "$worker_id"
    done
    echo "[${TIMESTAMP}] Все воркеры убиты"
else
    kill_worker "$1"
fi
