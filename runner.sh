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

POLL_INTERVAL=60        # секунд между проверками сигналов
MAX_RETRIES=2           # максимум retry для задачи
DRY_RUN=false
PLAN_FILE=""
PLAN_JSON=""

# Whitelist команд для acceptance_signals (command_succeeds, command_output_contains, no_syntax_errors)
ALLOWED_SIGNAL_COMMANDS=("pytest" "python3" "python" "node" "bash" "cat" "wc" "grep" "head" "tail" "npm" "npx" "go" "cargo" "make")

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

    log "INFO" "Жду ${total} сигналов. Проверка каждые ${POLL_INTERVAL}с..."

    while [[ $done_count -lt $total ]]; do
        sleep "$POLL_INTERVAL"

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
        fi
    done

    log "INFO" "Все ${total} сигналов получены"
}

# ─── Валидация команд для acceptance signals ─────────────────────────────────

validate_signal_command() {
    local cmd="$1"
    local base_cmd
    base_cmd=$(echo "$cmd" | awk '{print $1}')

    # Запрет опасных паттернов
    if echo "$cmd" | grep -qE '[;&|`$]|>|<|\beval\b|\bexec\b|\brm\b|\bsudo\b'; then
        log "WARN" "SECURITY: команда отклонена (опасный паттерн): ${cmd}"
        return 1
    fi

    # Проверка whitelist
    for allowed in "${ALLOWED_SIGNAL_COMMANDS[@]}"; do
        if [[ "$base_cmd" == "$allowed" ]]; then
            return 0
        fi
    done

    log "WARN" "SECURITY: команда не в whitelist: ${base_cmd}"
    return 1
}

# ─── Функции проверки отдельных signal types ─────────────────────────────────

check_signal_file_min_lines() {
    local path="$1" min_lines="$2"
    if [[ ! -f "$path" ]]; then
        log "WARN" "file_min_lines: файл не найден: ${path}"
        return 1
    fi
    local actual
    actual=$(wc -l < "$path" | tr -d ' ')
    if [[ "$actual" -lt "$min_lines" ]]; then
        log "WARN" "file_min_lines FAIL: ${path} имеет ${actual} строк, нужно >= ${min_lines}"
        return 1
    fi
    return 0
}

check_signal_file_max_lines() {
    local path="$1" max_lines="$2"
    if [[ ! -f "$path" ]]; then
        log "WARN" "file_max_lines: файл не найден: ${path}"
        return 1
    fi
    local actual
    actual=$(wc -l < "$path" | tr -d ' ')
    if [[ "$actual" -gt "$max_lines" ]]; then
        log "WARN" "file_max_lines FAIL: ${path} имеет ${actual} строк, максимум ${max_lines}"
        return 1
    fi
    return 0
}

check_signal_no_pattern() {
    local path="$1" pattern="$2"
    if [[ ! -f "$path" ]]; then
        log "WARN" "no_pattern: файл не найден: ${path}"
        return 1
    fi
    if grep -q "$pattern" "$path" 2>/dev/null; then
        log "WARN" "no_pattern FAIL: ${path} содержит запрещённый паттерн '${pattern}'"
        return 1
    fi
    return 0
}

check_signal_command_succeeds() {
    local cmd="$1"
    if ! validate_signal_command "$cmd"; then
        return 1
    fi
    if ! eval "$cmd" >/dev/null 2>&1; then
        log "WARN" "command_succeeds FAIL: ${cmd}"
        return 1
    fi
    return 0
}

check_signal_command_output_contains() {
    local cmd="$1" expected="$2"
    if ! validate_signal_command "$cmd"; then
        return 1
    fi
    local output
    output=$(eval "$cmd" 2>&1) || true
    if ! echo "$output" | grep -q "$expected"; then
        log "WARN" "command_output_contains FAIL: вывод '${cmd}' не содержит '${expected}'"
        return 1
    fi
    return 0
}

check_signal_no_syntax_errors() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        log "WARN" "no_syntax_errors: файл не найден: ${path}"
        return 1
    fi

    local ext="${path##*.}"
    case "$ext" in
        py)
            if ! python3 -c "compile(open('${path}').read(), '${path}', 'exec')" 2>/dev/null; then
                log "WARN" "no_syntax_errors FAIL: синтаксическая ошибка в ${path}"
                return 1
            fi
            ;;
        js|mjs)
            if command -v node &>/dev/null; then
                if ! node --check "$path" 2>/dev/null; then
                    log "WARN" "no_syntax_errors FAIL: синтаксическая ошибка в ${path}"
                    return 1
                fi
            else
                log "WARN" "no_syntax_errors: node не найден, пропускаю ${path}"
            fi
            ;;
        ts|tsx)
            if command -v npx &>/dev/null; then
                if ! npx tsc --noEmit "$path" 2>/dev/null; then
                    log "WARN" "no_syntax_errors FAIL: ошибка типизации в ${path}"
                    return 1
                fi
            else
                log "WARN" "no_syntax_errors: npx не найден, пропускаю ${path}"
            fi
            ;;
        sh|bash)
            if ! bash -n "$path" 2>/dev/null; then
                log "WARN" "no_syntax_errors FAIL: синтаксическая ошибка в ${path}"
                return 1
            fi
            ;;
        go)
            if command -v go &>/dev/null; then
                if ! go vet "$path" 2>/dev/null; then
                    log "WARN" "no_syntax_errors FAIL: ошибка в ${path}"
                    return 1
                fi
            fi
            ;;
        *)
            log "INFO" "no_syntax_errors: неизвестное расширение .${ext}, пропускаю ${path}"
            ;;
    esac
    return 0
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
            file_min_lines)
                local min_lines
                min_lines=$(jq -r ".acceptance_signals[${i}].min_lines" "$task_file")
                if ! check_signal_file_min_lines "$sig_path" "$min_lines"; then
                    return 1
                fi
                ;;
            file_max_lines)
                local max_lines
                max_lines=$(jq -r ".acceptance_signals[${i}].max_lines" "$task_file")
                if ! check_signal_file_max_lines "$sig_path" "$max_lines"; then
                    return 1
                fi
                ;;
            no_pattern)
                local pattern
                pattern=$(jq -r ".acceptance_signals[${i}].pattern" "$task_file")
                if ! check_signal_no_pattern "$sig_path" "$pattern"; then
                    return 1
                fi
                ;;
            command_succeeds)
                local cmd
                cmd=$(jq -r ".acceptance_signals[${i}].command" "$task_file")
                if ! check_signal_command_succeeds "$cmd"; then
                    return 1
                fi
                ;;
            command_output_contains)
                local cmd expected
                cmd=$(jq -r ".acceptance_signals[${i}].command" "$task_file")
                expected=$(jq -r ".acceptance_signals[${i}].expected" "$task_file")
                if ! check_signal_command_output_contains "$cmd" "$expected"; then
                    return 1
                fi
                ;;
            no_syntax_errors)
                if ! check_signal_no_syntax_errors "$sig_path"; then
                    return 1
                fi
                ;;
            *)
                log "WARN" "Неизвестный signal type: ${sig_type}, пропускаю"
                ;;
        esac

        i=$((i + 1))
    done

    log "INFO" "acceptance OK: ${task_id}"
    return 0
}

# ─── Проверка подозрительных результатов ──────────────────────────────────────

check_result_suspicious() {
    local task_id="$1"
    local result_path="${RESULTS_DIR}/${task_id}-result.md"
    local suspicious=false
    local reasons=""

    # 1. Результат отсутствует или пустой
    if [[ ! -f "$result_path" ]]; then
        log "WARN" "SUSPICIOUS ${task_id}: файл результата не найден"
        touch "${SIGNALS_DIR}/${task_id}.suspicious"
        return 1
    fi

    local size
    size=$(wc -c < "$result_path" | tr -d ' ')
    if [[ "$size" -lt 50 ]]; then
        suspicious=true
        reasons+="слишком маленький результат (${size} байт); "
    fi

    # 2. Ключевые слова ошибок в результате
    if grep -qiE '(error|traceback|exception|fatal|panic|cannot|unable to|не удалось|ошибка)' "$result_path" 2>/dev/null; then
        suspicious=true
        reasons+="содержит ключевые слова ошибок; "
    fi

    # 3. Результат содержит "не могу" / "не получилось" паттерны
    if grep -qiE '(не могу|не получилось|невозможно|I cannot|I could not|unable|I .* not able)' "$result_path" 2>/dev/null; then
        suspicious=true
        reasons+="воркер сообщил о невозможности выполнить задачу; "
    fi

    if $suspicious; then
        log "WARN" "SUSPICIOUS ${task_id}: ${reasons}"
        echo "$reasons" > "${SIGNALS_DIR}/${task_id}.suspicious"
        return 1
    fi

    return 0
}

# ─── Task-level checkpoint ───────────────────────────────────────────────────

call_task_checkpoint() {
    local task_id="$1"
    local phase_idx="$2"

    log "INFO" "Task checkpoint для ${task_id}"

    # Собрать контекст задачи
    local task_file="${TASKS_DIR}/${task_id}.json"
    local result_path="${RESULTS_DIR}/${task_id}-result.md"
    local context="Задача: ${task_id}\n"
    context+="Роль: $(jq -r '.role_required' "$task_file")\n"
    context+="Описание: $(jq -r '.title' "$task_file")\n\n"

    # Результат (первые 50 строк)
    if [[ -f "$result_path" ]]; then
        context+="Результат:\n$(head -50 "$result_path")\n\n"
    fi

    # Suspicious причины если есть
    if [[ -f "${SIGNALS_DIR}/${task_id}.suspicious" ]]; then
        context+="ВНИМАНИЕ — подозрительные признаки: $(cat "${SIGNALS_DIR}/${task_id}.suspicious")\n\n"
    fi

    # Acceptance signals результаты
    context+="Acceptance signals: "
    if check_acceptance "$task_id" 2>/dev/null; then
        context+="все прошли\n"
    else
        context+="ЕСТЬ ПРОБЛЕМЫ\n"
    fi

    context+="\nРежим: task-level checkpoint. Вердикт: ACCEPT / REWORK / ABORT\n"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN" "task_checkpoint: ${task_id}"
        return 0  # 0 = accept
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
        log "WARN" "Task checkpoint для ${task_id} failed, принимаю по умолчанию"
        return 0
    }

    # Сохранить результат checkpoint
    mkdir -p "${BRAIN_DIR}/checkpoints"
    echo "$response" > "${BRAIN_DIR}/checkpoints/${task_id}-checkpoint.json"

    local verdict
    verdict=$(echo "$response" | jq -r '.verdict // "ACCEPT"' 2>/dev/null || echo "ACCEPT")
    local reason
    reason=$(echo "$response" | jq -r '.reason // "нет"' 2>/dev/null || echo "нет")

    log "INFO" "Task checkpoint ${task_id}: ${verdict} — ${reason}"

    case "$verdict" in
        ACCEPT|CONTINUE) return 0 ;;
        REWORK) return 1 ;;
        ABORT) return 2 ;;
        *) return 0 ;;
    esac
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
            local acceptance_ok=true
            if ! check_acceptance "$task_id"; then
                log "WARN" "Задача ${task_id} done, но acceptance signals не прошли"
                acceptance_ok=false
                all_ok=false
            fi

            # Проверить подозрительный результат
            local suspicious=false
            if ! check_result_suspicious "$task_id"; then
                suspicious=true
            fi

            # Task-level checkpoint: для critical/checkpoint_after задач или suspicious
            local is_critical is_checkpoint_after
            is_critical=$(jq_plan ".phases[${phase_idx}].tasks[${i}].critical // false")
            is_checkpoint_after=$(jq_plan ".phases[${phase_idx}].tasks[${i}].checkpoint_after // false")

            if [[ "$is_critical" == "true" ]] || [[ "$is_checkpoint_after" == "true" ]] || $suspicious; then
                if [[ "$DRY_RUN" != "true" ]]; then
                    call_task_checkpoint "$task_id" "$phase_idx"
                    local cp_result=$?
                    case $cp_result in
                        0) ;; # ACCEPT
                        1) # REWORK
                            log "WARN" "Task checkpoint: REWORK для ${task_id}"
                            all_ok=false
                            ;;
                        2) # ABORT
                            die "Task checkpoint ABORT для ${task_id}"
                            ;;
                    esac
                fi
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

    # Собрать список файлов для ревью (owned_files из всех задач)
    local review_files=""
    p=0
    while [[ $p -lt $phase_count ]]; do
        local tc
        tc=$(jq_plan ".phases[${p}].tasks | length")
        local j=0
        while [[ $j -lt $tc ]]; do
            local files_list
            files_list=$(jq_plan ".phases[${p}].tasks[${j}].owned_files // [] | .[]")
            for f in $files_list; do
                [[ -f "$f" ]] && review_files+="- ${f}\n"
            done
            j=$((j + 1))
        done
        p=$((p + 1))
    done
    context+="\nФайлы для ревью:\n${review_files}"

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

        # Обновить state: phase done + счётчики
        local done_count
        done_count=$(find "$SIGNALS_DIR" -name "*.done" 2>/dev/null | wc -l | tr -d ' ')
        local failed_count
        failed_count=$(find "$SIGNALS_DIR" -name "*.failed" 2>/dev/null | wc -l | tr -d ' ')
        update_state ".phases[${p}].status = \"done\" | .tasks_done = ${done_count} | .tasks_failed = ${failed_count}"

        # Checkpoint (кроме последней фазы)
        run_checkpoint "$p" "$((p + 1))"

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
