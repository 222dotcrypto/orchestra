#!/usr/bin/env bash
# monitor.sh — Показать статус системы Orchestra v3
# Использование: bash .brain/scripts/monitor.sh [--watch]

set -euo pipefail

BRAIN_DIR=".brain"
TMUX_SESSION="orchestra"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

show_status() {
    clear 2>/dev/null || true
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}          ORCHESTRA v3 MONITOR              ${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════${NC}"
    echo ""

    # Состояние оркестратора
    if [[ -f "${BRAIN_DIR}/state.json" ]]; then
        echo -e "${BOLD}State${NC}"
        echo -e "───────────────────────────────────────────"
        if command -v jq &> /dev/null; then
            local status task phase tasks_done tasks_total tasks_failed next_action
            status=$(jq -r '.status // "unknown"' "${BRAIN_DIR}/state.json")
            task=$(jq -r '.current_task // "—"' "${BRAIN_DIR}/state.json")
            phase=$(jq -r '.current_phase // 0' "${BRAIN_DIR}/state.json")
            tasks_done=$(jq -r '.tasks_done // 0' "${BRAIN_DIR}/state.json")
            tasks_total=$(jq -r '.tasks_total // 0' "${BRAIN_DIR}/state.json")
            tasks_failed=$(jq -r '.tasks_failed // 0' "${BRAIN_DIR}/state.json")
            next_action=$(jq -r '.next_action // "—"' "${BRAIN_DIR}/state.json")

            local phase_count
            phase_count=$(jq -r '.phases | length // 0' "${BRAIN_DIR}/state.json")

            local status_color="${NC}"
            case "$status" in
                "done") status_color="${GREEN}" ;;
                "executing") status_color="${BLUE}" ;;
                "idle") status_color="${YELLOW}" ;;
                "failed") status_color="${RED}" ;;
            esac

            echo -e "  Статус:     ${status_color}${BOLD}${status}${NC}"
            echo -e "  Задача:     ${task}"
            echo -e "  Фаза:       ${phase}/${phase_count}"
            echo -e "  Прогресс:   ${GREEN}${tasks_done}${NC} done / ${RED}${tasks_failed}${NC} failed / ${tasks_total} total"
            echo -e "  Next:       ${next_action}"
        else
            cat "${BRAIN_DIR}/state.json"
        fi
    else
        echo -e "${YELLOW}  state.json не найден${NC}"
    fi
    echo ""

    # Runner
    echo -e "${BOLD}Runner${NC}"
    echo -e "───────────────────────────────────────────"
    local runner_pid
    runner_pid=$(pgrep -f "runner.sh" 2>/dev/null | head -1 || true)
    if [[ -n "$runner_pid" ]]; then
        echo -e "  PID: ${GREEN}${runner_pid}${NC} (работает)"
    else
        echo -e "  ${YELLOW}Не запущен${NC}"
    fi

    # Последний checkpoint из лога
    if [[ -f "${BRAIN_DIR}/logs/runner.log" ]]; then
        local last_checkpoint
        last_checkpoint=$(grep "Checkpoint:" "${BRAIN_DIR}/logs/runner.log" 2>/dev/null | tail -1 || true)
        if [[ -n "$last_checkpoint" ]]; then
            echo -e "  Checkpoint: ${last_checkpoint}"
        fi
    fi
    echo ""

    # Сигналы
    echo -e "${BOLD}Signals${NC}"
    echo -e "───────────────────────────────────────────"
    local done_count=0 failed_count=0
    done_count=$(find "${BRAIN_DIR}/signals" -name "*.done" 2>/dev/null | wc -l | tr -d ' ')
    failed_count=$(find "${BRAIN_DIR}/signals" -name "*.failed" 2>/dev/null | wc -l | tr -d ' ')

    if [[ $done_count -gt 0 ]] || [[ $failed_count -gt 0 ]]; then
        [[ $done_count -gt 0 ]] && echo -e "  ${GREEN}${done_count} .done${NC}"
        [[ $failed_count -gt 0 ]] && echo -e "  ${RED}${failed_count} .failed${NC}"
        # Список сигналов
        for sig in "${BRAIN_DIR}"/signals/*.done "${BRAIN_DIR}"/signals/*.failed; do
            [[ -f "$sig" ]] || continue
            local name ext
            name=$(basename "$sig")
            ext="${name##*.}"
            name="${name%.*}"
            local color="${GREEN}"
            [[ "$ext" == "failed" ]] && color="${RED}"
            echo -e "    ${color}${name}.${ext}${NC}"
        done
    else
        echo -e "  ${YELLOW}Нет сигналов${NC}"
    fi
    echo ""

    # Воркеры
    echo -e "${BOLD}Workers${NC}"
    echo -e "───────────────────────────────────────────"
    local worker_count=0
    for wf in "${BRAIN_DIR}"/workers/worker-*.json; do
        [[ -f "$wf" ]] || continue
        worker_count=$((worker_count + 1))
        if command -v jq &> /dev/null; then
            local wid wrole wstatus wtask
            wid=$(jq -r '.id' "$wf")
            wrole=$(jq -r '.role' "$wf")
            wstatus=$(jq -r '.status' "$wf")
            wtask=$(jq -r '.current_task // "—"' "$wf")

            local wicon="  "
            case "$wstatus" in
                "idle") wicon="${YELLOW}IDLE${NC}" ;;
                "busy") wicon="${GREEN}BUSY${NC}" ;;
                "stuck") wicon="${RED}STUCK${NC}" ;;
                "dead") wicon="${RED}DEAD${NC}" ;;
            esac

            echo -e "  ${BOLD}${wid}${NC} [${wrole}] ${wicon} task:${wtask}"
        else
            echo "  $(basename "$wf" .json)"
        fi
    done
    if [[ $worker_count -eq 0 ]]; then
        echo -e "  ${YELLOW}Нет воркеров${NC}"
    fi
    echo ""

    # Задачи
    echo -e "${BOLD}Tasks${NC}"
    echo -e "───────────────────────────────────────────"
    local task_count=0
    for tf in "${BRAIN_DIR}"/tasks/task-*.json; do
        [[ -f "$tf" ]] || continue
        task_count=$((task_count + 1))
        if command -v jq &> /dev/null; then
            local tid tstatus tassigned
            tid=$(jq -r '.id' "$tf")
            tstatus=$(jq -r '.status' "$tf")
            tassigned=$(jq -r '.assigned_to // "—"' "$tf")

            local tcolor="${NC}"
            case "$tstatus" in
                "done") tcolor="${GREEN}" ;;
                "in_progress") tcolor="${BLUE}" ;;
                "assigned") tcolor="${CYAN}" ;;
                "failed") tcolor="${RED}" ;;
            esac

            echo -e "  ${BOLD}${tid}${NC} ${tcolor}${tstatus}${NC} → ${tassigned}"
        else
            echo "  $(basename "$tf" .json)"
        fi
    done
    if [[ $task_count -eq 0 ]]; then
        echo -e "  ${YELLOW}Нет задач${NC}"
    fi
    echo ""

    # tmux окна
    echo -e "${BOLD}tmux${NC}"
    echo -e "───────────────────────────────────────────"
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        tmux list-windows -t "$TMUX_SESSION" -F "  #{window_index}: #{window_name} #{?window_active,(active),}" 2>/dev/null
    else
        echo -e "  ${YELLOW}Сессия '${TMUX_SESSION}' не найдена${NC}"
    fi
    echo ""
    echo -e "${CYAN}───────────────────────────────────────────${NC}"
    echo -e "  $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
}

# Режим наблюдения
if [[ "${1:-}" == "--watch" ]]; then
    echo "Режим наблюдения (Ctrl+C для выхода)..."
    while true; do
        show_status
        sleep 5
    done
else
    show_status
fi
