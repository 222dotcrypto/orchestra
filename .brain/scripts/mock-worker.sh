#!/usr/bin/env bash
# mock-worker.sh — Мок-воркер для тестирования runner.sh
# Имитирует работу воркера: читает задачу, создаёт файлы, шлёт сигнал
# Использование: bash .brain/scripts/mock-worker.sh <worker-id>

set -euo pipefail

BRAIN_DIR=".brain"
WORKER_ID="${1:?Ошибка: укажи worker-id}"

# Найти задачу
TASK_FILE=$(find "${BRAIN_DIR}/tasks" -name "*.json" -exec grep -l "\"assigned_to\": \"${WORKER_ID}\"" {} \; | head -1)
[[ -n "$TASK_FILE" ]] || { echo "Задача для ${WORKER_ID} не найдена"; exit 1; }

TASK_ID=$(jq -r '.id' "$TASK_FILE")
RESULT_PATH=$(jq -r '.result_path' "$TASK_FILE")

# Обновить статус задачи
jq '.status = "in_progress"' "$TASK_FILE" > /tmp/task.tmp && mv /tmp/task.tmp "$TASK_FILE"

# Создать файлы из acceptance_signals
local_sig_count=$(jq '.acceptance_signals | length' "$TASK_FILE")
i=0
while [[ $i -lt $local_sig_count ]]; do
    sig_type=$(jq -r ".acceptance_signals[${i}].type" "$TASK_FILE")
    sig_path=$(jq -r ".acceptance_signals[${i}].path" "$TASK_FILE")

    case "$sig_type" in
        file_exists)
            mkdir -p "$(dirname "$sig_path")"
            touch "$sig_path"
            ;;
        file_contains)
            pattern=$(jq -r ".acceptance_signals[${i}].pattern" "$TASK_FILE")
            mkdir -p "$(dirname "$sig_path")"
            echo "$pattern" >> "$sig_path"
            ;;
    esac
    i=$((i + 1))
done

# Записать результат
mkdir -p "$(dirname "$RESULT_PATH")"
echo "# Результат ${TASK_ID}" > "$RESULT_PATH"
echo "Mock worker ${WORKER_ID} выполнил задачу." >> "$RESULT_PATH"

# Обновить статус задачи
jq '.status = "done"' "$TASK_FILE" > /tmp/task.tmp && mv /tmp/task.tmp "$TASK_FILE"

# Создать сигнал
touch "${BRAIN_DIR}/signals/${TASK_ID}.done"

echo "Mock worker ${WORKER_ID}: задача ${TASK_ID} выполнена"
