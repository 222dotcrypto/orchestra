#!/usr/bin/env bash
# runner.sh — Orchestra v3 Shell Runner
# Исполняет plan.yaml: спавнит воркеров, ждёт сигналы, запускает checkpoint/reviewer
#
# Использование:
#   bash runner.sh plan.yaml
#   bash runner.sh --dry-run plan.yaml

set -euo pipefail

# ─── Конфигурация ───────────────────────────────────────────────────────────

BRAIN_DIR=".brain"
SCRIPTS_DIR="${BRAIN_DIR}/scripts"
SIGNALS_DIR="${BRAIN_DIR}/signals"
TASKS_DIR="${BRAIN_DIR}/tasks"
PROMPTS_DIR="${BRAIN_DIR}/prompts"
RESULTS_DIR="${BRAIN_DIR}/results"
WORKERS_DIR="${BRAIN_DIR}/workers"
LOGS_DIR="${BRAIN_DIR}/logs"
LOG_FILE="${LOGS_DIR}/runner.log"

POLL_INTERVAL=30        # секунд между проверками сигналов
INITIAL_WAIT=180        # секунд до первой проверки (воркеры не готовы раньше)
MAX_RETRIES=2           # максимум retry для задачи
DRY_RUN=false
PLAN_FILE=""
PLAN_JSON=""

# ─── Утилиты ────────────────────────────────────────────────────────────────

log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "[${ts}] ${level}: ${msg}" | tee -a "$LOG_FILE"
}

die() { log "FATAL" "$*"; exit 1; }

safe_path() {
    local p="$1"
    local resolved
    resolved=$(cd "$(dirname "$p")" 2>/dev/null && pwd)/$(basename "$p") || return 1
    local project_root
    project_root=$(pwd)
    [[ "$resolved" == "$project_root"* ]] || return 1
}

update_state() {
    local updates="$1"
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg ts "$ts" "${updates} | .updated_at = \$ts" \
        "${BRAIN_DIR}/state.json" > /tmp/state.tmp && mv /tmp/state.tmp "${BRAIN_DIR}/state.json"
}

jq_plan() {
    echo "$PLAN_JSON" | jq -r "$@"
}

# ─── Парсинг плана ──────────────────────────────────────────────────────────

parse_plan() {
    local plan_file="$1"
    [[ -f "$plan_file" ]] || die "План не найден: ${plan_file}"

    if ! command -v python3 &>/dev/null; then
        die "python3 не найден (нужен для парсинга YAML)"
    fi

    PLAN_JSON=$(python3 "${SCRIPTS_DIR}/yaml_to_json.py" < "$plan_file") \
        || die "Ошибка парсинга YAML"

    local name complexity phase_count
    name=$(jq_plan '.name')
    complexity=$(jq_plan '.complexity')
    phase_count=$(jq_plan '.phases | length')

    log "INFO" "План: ${name} | Сложность: ${complexity} | Фаз: ${phase_count}"
}

# ─── Создание задач и промптов для фазы ─────────────────────────────────────

spawn_phase() {
    local phase_idx="$1"  # 0-based index
    local phase_id phase_name task_count
    phase_id=$(jq_plan ".phases[${phase_idx}].id")
    phase_name=$(jq_plan ".phases[${phase_idx}].name")
    task_count=$(jq_plan ".phases[${phase_idx}].tasks | length")

    log "INFO" "═══ Фаза ${phase_id}: ${phase_name} (${task_count} задач) ═══"

    local i=0
    while [[ $i -lt $task_count ]]; do
        local task_id role prompt timeout on_failure
        task_id=$(jq_plan ".phases[${phase_idx}].tasks[${i}].id")
        role=$(jq_plan ".phases[${phase_idx}].tasks[${i}].role")
        prompt=$(jq_plan ".phases[${phase_idx}].tasks[${i}].prompt")
        timeout=$(jq_plan ".phases[${phase_idx}].tasks[${i}].timeout // 600")
        on_failure=$(jq_plan ".phases[${phase_idx}].tasks[${i}].on_failure // \"retry\"")

        # owned_files как JSON-массив
        local owned_files
        owned_files=$(jq_plan ".phases[${phase_idx}].tasks[${i}].owned_files // []")

        # acceptance_signals как JSON-массив
        local signals
        signals=$(jq_plan ".phases[${phase_idx}].tasks[${i}].acceptance_signals // []")

        # Worker ID = task ID без "task-" → "worker-XXX"
        local worker_id="worker-${task_id#task-}"

        # Создать task JSON
        local task_json
        task_json=$(jq -n \
            --arg id "$task_id" \
            --argjson phase "$phase_id" \
            --arg title "$prompt" \
            --arg desc "$prompt" \
            --arg role "$role" \
            --arg worker "$worker_id" \
            --argjson owned "$owned_files" \
            --argjson signals "$signals" \
            --arg result_path "${RESULTS_DIR}/${task_id}-result.md" \
            --argjson timeout "$timeout" \
            --arg on_failure "$on_failure" \
            '{
                id: $id, phase: $phase, title: ($desc | split("\n") | first),
                description: $desc, role_required: $role, assigned_to: $worker,
                status: "assigned", priority: "high", depends_on: [],
                owned_files: $owned, acceptance_criteria: [],
                acceptance_signals: $signals,
                context_files: [], result_path: $result_path,
                timeout: $timeout, on_failure: $on_failure,
                rework_count: 0, rework_comment: "",
                created_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
                updated_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
            }')

        echo "$task_json" > "/tmp/${task_id}.tmp" && mv "/tmp/${task_id}.tmp" "${TASKS_DIR}/${task_id}.json"
        log "INFO" "Задача ${task_id} создана → ${worker_id} (${role})"

        # Создать промпт воркера
        cat > "/tmp/${worker_id}.tmp" << PROMPT_EOF
# Воркер: ${role}

Ты — ${role} в команде Orchestra. Твой ID: ${worker_id}.

Прочитай \`.brain/WORKER_PROTOCOL.md\` — там протокол работы.
Найди свою задачу в \`.brain/tasks/\` (assigned_to: "${worker_id}", status: "assigned").
Логируй в \`.brain/logs/${worker_id}.log\`.

## Задача
${prompt}
PROMPT_EOF
        mv "/tmp/${worker_id}.tmp" "${PROMPTS_DIR}/${worker_id}.md"

        # Запустить воркера
        if [[ "$DRY_RUN" == "true" ]]; then
            log "DRY-RUN" "spawn-worker.sh ${worker_id} ${role}"
        else
            bash "${SCRIPTS_DIR}/spawn-worker.sh" "$worker_id" "$role"
        fi

        i=$((i + 1))
    done
}

# ─── Ожидание сигналов ──────────────────────────────────────────────────────

wait_for_signals() {
    local phase_idx="$1"
    local task_count
    task_count=$(jq_plan ".phases[${phase_idx}].tasks | length")

    # Собрать все task IDs фазы
    local task_ids=()
    local i=0
    while [[ $i -lt $task_count ]]; do
        task_ids+=($(jq_plan ".phases[${phase_idx}].tasks[${i}].id"))
        i=$((i + 1))
    done

    local total=${#task_ids[@]}
    local done_count=0

    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN" "wait_for_signals: ${task_ids[*]}"
        return 0
    fi

    log "INFO" "Жду ${total} сигналов. Первая проверка через ${INITIAL_WAIT}с..."
    sleep "$INITIAL_WAIT"

    while [[ $done_count -lt $total ]]; do
        done_count=0
        for tid in "${task_ids[@]}"; do
            if [[ -f "${SIGNALS_DIR}/${tid}.done" ]] || [[ -f "${SIGNALS_DIR}/${tid}.failed" ]]; then
                done_count=$((done_count + 1))
            fi
        done

        log "INFO" "Сигналы: ${done_count}/${total}"

        if [[ $done_count -lt $total ]]; then
            # Проверить здоровье воркеров
            bash "${SCRIPTS_DIR}/check-workers.sh" 2>/dev/null || true
            sleep "$POLL_INTERVAL"
        fi
    done

    log "INFO" "Все ${total} сигналов получены"
}

# ─── Проверка acceptance signals ─────────────────────────────────────────────

check_acceptance() {
    local task_id="$1"
    local task_file="${TASKS_DIR}/${task_id}.json"
    local signal_count
    signal_count=$(jq '.acceptance_signals | length' "$task_file")

    [[ "$signal_count" -eq 0 ]] && return 0

    local i=0
    while [[ $i -lt $signal_count ]]; do
        local sig_type sig_path
        sig_type=$(jq -r ".acceptance_signals[${i}].type" "$task_file")
        sig_path=$(jq -r ".acceptance_signals[${i}].path" "$task_file")

        case "$sig_type" in
            file_exists)
                if [[ ! -f "$sig_path" ]]; then
                    log "WARN" "acceptance FAIL: ${sig_path} не существует"
                    return 1
                fi
                ;;
            file_contains)
                local pattern
                pattern=$(jq -r ".acceptance_signals[${i}].pattern" "$task_file")
                if ! grep -q "$pattern" "$sig_path" 2>/dev/null; then
                    log "WARN" "acceptance FAIL: ${sig_path} не содержит '${pattern}'"
                    return 1
                fi
                ;;
        esac

        i=$((i + 1))
    done

    log "INFO" "acceptance OK: ${task_id}"
    return 0
}

# ─── Обработка результатов фазы ─────────────────────────────────────────────

process_phase_results() {
    local phase_idx="$1"
    local task_count
    task_count=$(jq_plan ".phases[${phase_idx}].tasks | length")

    local all_ok=true
    local i=0
    while [[ $i -lt $task_count ]]; do
        local task_id on_failure
        task_id=$(jq_plan ".phases[${phase_idx}].tasks[${i}].id")
        on_failure=$(jq_plan ".phases[${phase_idx}].tasks[${i}].on_failure // \"retry\"")

        if [[ -f "${SIGNALS_DIR}/${task_id}.failed" ]]; then
            log "WARN" "Задача ${task_id} FAILED"
            case "$on_failure" in
                retry)
                    local retries
                    retries=$(jq -r '.rework_count // 0' "${TASKS_DIR}/${task_id}.json")
                    if [[ $retries -lt $MAX_RETRIES ]]; then
                        log "INFO" "Retry ${task_id} (попытка $((retries + 1))/${MAX_RETRIES})"
                        # Очистить сигнал и перезапустить
                        rm -f "${SIGNALS_DIR}/${task_id}.failed"
                        jq --argjson r "$((retries + 1))" '.rework_count = $r | .status = "assigned"' \
                            "${TASKS_DIR}/${task_id}.json" > /tmp/task.tmp \
                            && mv /tmp/task.tmp "${TASKS_DIR}/${task_id}.json"
                        local worker_id="worker-${task_id#task-}"
                        local role
                        role=$(jq -r '.role_required' "${TASKS_DIR}/${task_id}.json")
                        bash "${SCRIPTS_DIR}/kill-worker.sh" "$worker_id" 2>/dev/null || true
                        bash "${SCRIPTS_DIR}/spawn-worker.sh" "$worker_id" "$role"
                        all_ok=false  # нужно ждать ещё
                    else
                        log "ERROR" "Задача ${task_id} исчерпала retry (${MAX_RETRIES})"
                        all_ok=false
                    fi
                    ;;
                skip)
                    log "INFO" "Задача ${task_id} пропущена (on_failure: skip)"
                    ;;
                abort)
                    log "ERROR" "Задача ${task_id} failed → ABORT"
                    die "Абортировано по on_failure: abort для ${task_id}"
                    ;;
            esac
        elif [[ -f "${SIGNALS_DIR}/${task_id}.done" ]]; then
            # Проверить acceptance signals
            if ! check_acceptance "$task_id"; then
                log "WARN" "Задача ${task_id} done, но acceptance signals не прошли"
                all_ok=false
            fi
        fi

        i=$((i + 1))
    done

    $all_ok
}

# ─── Checkpoint ──────────────────────────────────────────────────────────────

run_checkpoint() {
    local completed_phase_idx="$1"
    local next_phase_idx="$2"
    local total_phases
    total_phases=$(jq_plan '.phases | length')

    # Последняя фаза — checkpoint не нужен
    [[ $next_phase_idx -ge $total_phases ]] && return 0

    log "INFO" "Запуск checkpoint между фазами ${completed_phase_idx} и ${next_phase_idx}"

    # Собрать контекст
    local context="Завершена фаза $((completed_phase_idx + 1)).\n\n"
    context+="Результаты:\n"

    local task_count
    task_count=$(jq_plan ".phases[${completed_phase_idx}].tasks | length")
    local i=0
    while [[ $i -lt $task_count ]]; do
        local tid
        tid=$(jq_plan ".phases[${completed_phase_idx}].tasks[${i}].id")
        if [[ -f "${SIGNALS_DIR}/${tid}.done" ]]; then
            context+="- ${tid}: DONE\n"
        elif [[ -f "${SIGNALS_DIR}/${tid}.failed" ]]; then
            context+="- ${tid}: FAILED\n"
        fi
        i=$((i + 1))
    done

    context+="\nСледующая фаза: $(jq_plan ".phases[${next_phase_idx}].name")\n"
    context+="Задачи следующей фазы:\n"
    task_count=$(jq_plan ".phases[${next_phase_idx}].tasks | length")
    i=0
    while [[ $i -lt $task_count ]]; do
        local tid role
        tid=$(jq_plan ".phases[${next_phase_idx}].tasks[${i}].id")
        role=$(jq_plan ".phases[${next_phase_idx}].tasks[${i}].role")
        context+="- ${tid} (${role})\n"
        i=$((i + 1))
    done

    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN" "checkpoint: context=${context}"
        return 0
    fi

    local checkpoint_prompt
    checkpoint_prompt=$(cat "${BRAIN_DIR}/prompts/templates/checkpoint.md")

    local response
    response=$(unset CLAUDECODE; claude \
        --dangerously-skip-permissions \
        --system-prompt "$checkpoint_prompt" \
        -p "$(echo -e "$context")" \
        --output-format text \
        2>/dev/null) || {
        log "WARN" "Checkpoint вызов failed, продолжаю (CONTINUE по умолчанию)"
        return 0
    }

    local verdict
    verdict=$(echo "$response" | jq -r '.verdict // "CONTINUE"' 2>/dev/null || echo "CONTINUE")
    local reason
    reason=$(echo "$response" | jq -r '.reason // "нет"' 2>/dev/null || echo "нет")

    log "INFO" "Checkpoint: ${verdict} — ${reason}"

    case "$verdict" in
        CONTINUE) return 0 ;;
        ADJUST)
            log "INFO" "Checkpoint ADJUST — применяю корректировки"
            # TODO: применить adjustments (skip задачи, modify prompts)
            return 0
            ;;
        ABORT)
            die "Checkpoint ABORT: ${reason}"
            ;;
        *)
            log "WARN" "Неизвестный verdict: ${verdict}, продолжаю"
            return 0
            ;;
    esac
}

# ─── Reviewer ────────────────────────────────────────────────────────────────

run_reviewer() {
    log "INFO" "Запуск финального ревью"

    # Собрать все результаты
    local context="Финальное ревью задачи: $(jq_plan '.name')\n\n"
    context+="Результаты:\n"

    local phase_count
    phase_count=$(jq_plan '.phases | length')
    local p=0
    while [[ $p -lt $phase_count ]]; do
        local task_count
        task_count=$(jq_plan ".phases[${p}].tasks | length")
        local i=0
        while [[ $i -lt $task_count ]]; do
            local tid result_path
            tid=$(jq_plan ".phases[${p}].tasks[${i}].id")
            result_path="${RESULTS_DIR}/${tid}-result.md"
            if [[ -f "$result_path" ]]; then
                context+="--- ${tid} ---\n$(head -50 "$result_path")\n\n"
            fi
            i=$((i + 1))
        done
        p=$((p + 1))
    done

    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN" "reviewer: контекст собран"
        return 0
    fi

    local reviewer_prompt
    reviewer_prompt=$(cat "${BRAIN_DIR}/prompts/templates/reviewer.md")

    local review_ts
    review_ts=$(date +%Y%m%d-%H%M%S)
    local review_file="${BRAIN_DIR}/review/results/review-${review_ts}.md"
    mkdir -p "${BRAIN_DIR}/review/results"

    local response
    response=$(unset CLAUDECODE; claude \
        --dangerously-skip-permissions \
        --system-prompt "$reviewer_prompt" \
        -p "$(echo -e "$context")" \
        --output-format text \
        2>/dev/null) || {
        log "WARN" "Reviewer вызов failed"
        return 1
    }

    echo "$response" > "$review_file"
    log "INFO" "Ревью записано в ${review_file}"

    # Парсить JSON-вердикт из <review-json> тега
    local verdict
    verdict=$(echo "$response" | sed -n '/<review-json>/,/<\/review-json>/p' | grep -v 'review-json' | jq -r '.verdict // "PASS"' 2>/dev/null || echo "PASS")
    log "INFO" "Ревью вердикт: ${verdict}"
}

# ─── Cleanup ─────────────────────────────────────────────────────────────────

cleanup_phase() {
    local phase_idx="$1"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN" "cleanup фазы ${phase_idx}"
        return 0
    fi

    # Убить воркеров фазы
    local task_count
    task_count=$(jq_plan ".phases[${phase_idx}].tasks | length")
    local i=0
    while [[ $i -lt $task_count ]]; do
        local task_id="$(jq_plan ".phases[${phase_idx}].tasks[${i}].id")"
        local worker_id="worker-${task_id#task-}"
        bash "${SCRIPTS_DIR}/kill-worker.sh" "$worker_id" 2>/dev/null || true
        i=$((i + 1))
    done
}

# ─── Инициализация state.json ────────────────────────────────────────────────

init_state() {
    local name complexity phase_count task_count ts
    name=$(jq_plan '.name')
    complexity=$(jq_plan '.complexity')
    phase_count=$(jq_plan '.phases | length')
    task_count=$(jq_plan '[.phases[].tasks | length] | add')
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Собрать phases массив для state.json
    local phases_json="["
    local p=0
    while [[ $p -lt $phase_count ]]; do
        local pid ptasks
        pid=$(jq_plan ".phases[${p}].id")
        ptasks=$(jq_plan "[.phases[${p}].tasks[].id]")
        [[ $p -gt 0 ]] && phases_json+=","
        phases_json+="{\"id\":${pid},\"status\":\"pending\",\"tasks\":${ptasks}}"
        p=$((p + 1))
    done
    phases_json+="]"

    cat > /tmp/state.tmp << EOF
{
  "status": "executing",
  "current_task": "${name}",
  "class": "${complexity}",
  "current_phase": 1,
  "phases": ${phases_json},
  "workers_active": 0,
  "tasks_total": ${task_count},
  "tasks_done": 0,
  "tasks_failed": 0,
  "next_action": "Фаза 1",
  "started_at": "${ts}",
  "updated_at": "${ts}"
}
EOF
    mv /tmp/state.tmp "${BRAIN_DIR}/state.json"
    log "INFO" "state.json инициализирован"
}

# ─── Основной цикл ──────────────────────────────────────────────────────────

main() {
    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=true; shift ;;
            --help|-h)
                echo "Использование: bash runner.sh [--dry-run] plan.yaml"
                exit 0
                ;;
            *)
                PLAN_FILE="$1"; shift ;;
        esac
    done

    [[ -n "$PLAN_FILE" ]] || die "Укажи файл плана: bash runner.sh plan.yaml"
    [[ -d "$BRAIN_DIR" ]] || die ".brain/ не найден. Запусти из корня проекта Orchestra"

    mkdir -p "$LOGS_DIR" "$SIGNALS_DIR" "$TASKS_DIR" "$PROMPTS_DIR" "$RESULTS_DIR" "$WORKERS_DIR"

    log "INFO" "═══════════════════════════════════════"
    log "INFO" "Orchestra Runner v3 запущен"
    [[ "$DRY_RUN" == "true" ]] && log "INFO" "*** DRY-RUN MODE ***"

    # Парсинг плана
    parse_plan "$PLAN_FILE"

    # Инициализация state.json
    init_state

    # Основной цикл по фазам
    local phase_count
    phase_count=$(jq_plan '.phases | length')
    local p=0

    while [[ $p -lt $phase_count ]]; do
        local phase_id
        phase_id=$(jq_plan ".phases[${p}].id")

        update_state ".current_phase = ${phase_id} | .next_action = \"Фаза ${phase_id}\""

        # Спавн воркеров фазы
        spawn_phase "$p"

        # Ожидание сигналов
        wait_for_signals "$p"

        # Обработка результатов
        if ! process_phase_results "$p"; then
            log "WARN" "Фаза ${phase_id}: есть проблемы, проверяю retry..."
            # Если retry запущены — ждём ещё раз
            wait_for_signals "$p"
            process_phase_results "$p" || log "ERROR" "Фаза ${phase_id}: проблемы остались после retry"
        fi

        # Cleanup воркеров фазы
        cleanup_phase "$p"

        # Checkpoint (кроме последней фазы)
        run_checkpoint "$p" "$((p + 1))"

        # Обновить state
        local done_count
        done_count=$(find "$SIGNALS_DIR" -name "*.done" 2>/dev/null | wc -l | tr -d ' ')
        local failed_count
        failed_count=$(find "$SIGNALS_DIR" -name "*.failed" 2>/dev/null | wc -l | tr -d ' ')
        update_state ".tasks_done = ${done_count} | .tasks_failed = ${failed_count}"

        p=$((p + 1))
    done

    # Финальное ревью
    run_reviewer

    # Завершение
    update_state '.status = "done" | .next_action = "Завершено" | .workers_active = 0'

    # Очистить сигналы
    rm -f "${SIGNALS_DIR}"/*.done "${SIGNALS_DIR}"/*.failed

    log "INFO" "═══════════════════════════════════════"
    log "INFO" "Orchestra Runner завершён"
    log "INFO" "Результаты в ${RESULTS_DIR}/"
}

main "$@"
