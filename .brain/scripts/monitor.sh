#!/usr/bin/env bash
# monitor.sh — Показать статус всей системы Orchestra
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
    echo -e "${BOLD}${CYAN}          🎭 ORCHESTRA MONITOR             ${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════${NC}"
    echo ""

    # Состояние оркестратора
    if [[ -f "${BRAIN_DIR}/state.json" ]]; then
        echo -e "${BOLD}📊 Состояние оркестратора${NC}"
        echo -e "───────────────────────────────────────────"
        if command -v jq &> /dev/null; then
            local status=$(jq -r '.status // "unknown"' "${BRAIN_DIR}/state.json")
            local task=$(jq -r '.current_task // "нет"' "${BRAIN_DIR}/state.json")
            local phase=$(jq -r '.phase // 0' "${BRAIN_DIR}/state.json")
            local total_phases=$(jq -r '.total_phases // 0' "${BRAIN_DIR}/state.json")
            local tasks_done=$(jq -r '.tasks_done // 0' "${BRAIN_DIR}/state.json")
            local tasks_total=$(jq -r '.tasks_total // 0' "${BRAIN_DIR}/state.json")
            local workers=$(jq -r '.workers_active // 0' "${BRAIN_DIR}/state.json")

            local status_icon="⏳"
            case "$status" in
                "done") status_icon="✅" ;;
                "executing") status_icon="🔄" ;;
                "planning") status_icon="📝" ;;
                "reviewing") status_icon="🔍" ;;
                "failed") status_icon="❌" ;;
            esac

            echo -e "  Статус:   ${status_icon} ${status}"
            echo -e "  Задача:   ${task}"
            echo -e "  Фаза:     ${phase}/${total_phases}"
            echo -e "  Прогресс: ${tasks_done}/${tasks_total} задач"
            echo -e "  Воркеры:  ${workers} активных"
        else
            cat "${BRAIN_DIR}/state.json"
        fi
    else
        echo -e "${YELLOW}  state.json не найден${NC}"
    fi
    echo ""

    # Воркеры
    echo -e "${BOLD}👷 Воркеры${NC}"
    echo -e "───────────────────────────────────────────"
    local worker_count=0
    for wf in "${BRAIN_DIR}"/workers/worker-*.json; do
        [[ -f "$wf" ]] || continue
        worker_count=$((worker_count + 1))
        if command -v jq &> /dev/null; then
            local wid=$(jq -r '.id' "$wf")
            local wrole=$(jq -r '.role' "$wf")
            local wstatus=$(jq -r '.status' "$wf")
            local wtask=$(jq -r '.current_task // "—"' "$wf")
            local wheartbeat=$(jq -r '.last_heartbeat // "нет"' "$wf")

            local wicon="⚪"
            case "$wstatus" in
                "idle") wicon="💤" ;;
                "busy") wicon="🔨" ;;
                "stuck") wicon="🚨" ;;
                "dead") wicon="💀" ;;
            esac

            echo -e "  ${wicon} ${BOLD}${wid}${NC} [${wrole}] — ${wstatus}"
            echo -e "     Задача: ${wtask} | Heartbeat: ${wheartbeat}"
        else
            echo "  $(basename "$wf" .json)"
        fi
    done
    if [[ $worker_count -eq 0 ]]; then
        echo -e "  ${YELLOW}Нет активных воркеров${NC}"
    fi
    echo ""

    # Задачи
    echo -e "${BOLD}📋 Задачи${NC}"
    echo -e "───────────────────────────────────────────"
    local task_count=0
    for tf in "${BRAIN_DIR}"/tasks/task-*.json; do
        [[ -f "$tf" ]] || continue
        task_count=$((task_count + 1))
        if command -v jq &> /dev/null; then
            local tid=$(jq -r '.id' "$tf")
            local ttitle=$(jq -r '.title' "$tf")
            local tstatus=$(jq -r '.status' "$tf")
            local tassigned=$(jq -r '.assigned_to // "—"' "$tf")
            local tpriority=$(jq -r '.priority // "medium"' "$tf")

            local ticon="⬜"
            case "$tstatus" in
                "pending") ticon="⬜" ;;
                "assigned") ticon="📌" ;;
                "in_progress") ticon="🔄" ;;
                "review") ticon="🔍" ;;
                "done") ticon="✅" ;;
                "failed") ticon="❌" ;;
                "rework") ticon="🔙" ;;
            esac

            local pcolor="${NC}"
            case "$tpriority" in
                "high") pcolor="${RED}" ;;
                "medium") pcolor="${YELLOW}" ;;
                "low") pcolor="${GREEN}" ;;
            esac

            echo -e "  ${ticon} ${BOLD}${tid}${NC}: ${ttitle}"
            echo -e "     Статус: ${tstatus} | Воркер: ${tassigned} | Приоритет: ${pcolor}${tpriority}${NC}"
        else
            echo "  $(basename "$tf" .json)"
        fi
    done
    if [[ $task_count -eq 0 ]]; then
        echo -e "  ${YELLOW}Нет задач${NC}"
    fi
    echo ""

    # tmux окна
    echo -e "${BOLD}🖥  tmux окна${NC}"
    echo -e "───────────────────────────────────────────"
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        tmux list-windows -t "$TMUX_SESSION" -F "  🪟 #{window_index}: #{window_name} #{?window_active,(активно),}" 2>/dev/null
    else
        echo -e "  ${YELLOW}Сессия '${TMUX_SESSION}' не найдена${NC}"
    fi
    echo ""
    echo -e "${CYAN}───────────────────────────────────────────${NC}"
    echo -e "  Обновлено: $(date '+%Y-%m-%d %H:%M:%S')"
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
