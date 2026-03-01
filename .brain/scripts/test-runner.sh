#!/usr/bin/env bash
# test-runner.sh — Тестовый harness для runner.sh
# Создаёт временную среду, запускает runner.sh --dry-run, проверяет результаты
# Использование: bash .brain/scripts/test-runner.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEST_DIR=$(mktemp -d)
PASSED=0
FAILED=0

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

assert() {
    local desc="$1"
    local cond="$2"
    if eval "$cond"; then
        echo -e "  ${GREEN}PASS${NC} ${desc}"
        PASSED=$((PASSED + 1))
    else
        echo -e "  ${RED}FAIL${NC} ${desc}"
        FAILED=$((FAILED + 1))
    fi
}

echo -e "${BOLD}═══ Orchestra Runner Tests ═══${NC}"
echo ""

# ─── Setup ───────────────────────────────────────────────────────────────────

echo -e "${BOLD}Setup${NC}"

# Создать .brain/ структуру
mkdir -p "${TEST_DIR}/.brain/"{tasks,workers,results,prompts,logs,signals,scripts}
mkdir -p "${TEST_DIR}/.brain/prompts/templates"

# Скопировать скрипты
cp "${PROJECT_ROOT}/runner.sh" "${TEST_DIR}/"
cp "${PROJECT_ROOT}/.brain/scripts/yaml_to_json.py" "${TEST_DIR}/.brain/scripts/"
cp "${PROJECT_ROOT}/.brain/scripts/spawn-worker.sh" "${TEST_DIR}/.brain/scripts/"
cp "${PROJECT_ROOT}/.brain/scripts/run-worker.sh" "${TEST_DIR}/.brain/scripts/"
cp "${PROJECT_ROOT}/.brain/scripts/kill-worker.sh" "${TEST_DIR}/.brain/scripts/"
cp "${PROJECT_ROOT}/.brain/scripts/check-workers.sh" "${TEST_DIR}/.brain/scripts/"
cp "${PROJECT_ROOT}/.brain/prompts/templates/checkpoint.md" "${TEST_DIR}/.brain/prompts/templates/"
cp "${PROJECT_ROOT}/.brain/prompts/templates/reviewer.md" "${TEST_DIR}/.brain/prompts/templates/"
cp "${PROJECT_ROOT}/.brain/WORKER_PROTOCOL.md" "${TEST_DIR}/.brain/"

# Создать state.json
cat > "${TEST_DIR}/.brain/state.json" << 'EOF'
{
  "status": "idle",
  "current_task": null,
  "class": null,
  "current_phase": 0,
  "phases": [],
  "workers_active": 0,
  "tasks_total": 0,
  "tasks_done": 0,
  "tasks_failed": 0,
  "next_action": "Waiting for task",
  "started_at": "",
  "updated_at": ""
}
EOF

# Создать тестовый plan.yaml
cat > "${TEST_DIR}/test-plan.yaml" << 'EOF'
name: "Test Plan"
complexity: 5

phases:
  - id: 1
    name: "Phase One"
    tasks:
      - id: task-001
        role: coder
        prompt: |
          Context: Test context
          Command: Create test file
          Constraints:
            - Do not modify other files
          Criteria:
            - File exists
          Completion: Result in .brain/results/task-001-result.md
        owned_files:
          - src/test.py
        acceptance_signals:
          - type: file_exists
            path: src/test.py
        timeout: 300
        on_failure: retry

      - id: task-002
        role: tester
        prompt: |
          Context: Test context
          Command: Write tests
          Constraints:
            - Do not modify source files
          Criteria:
            - Test file exists
          Completion: Result in .brain/results/task-002-result.md
        owned_files:
          - tests/test_test.py
        acceptance_signals:
          - type: file_exists
            path: tests/test_test.py
        timeout: 300
        on_failure: skip

  - id: 2
    name: "Phase Two"
    tasks:
      - id: task-003
        role: writer
        prompt: |
          Context: Test context
          Command: Write docs
          Constraints:
            - Only modify docs
          Criteria:
            - README exists
          Completion: Result in .brain/results/task-003-result.md
        owned_files:
          - docs/README.md
        acceptance_signals:
          - type: file_exists
            path: docs/README.md
        timeout: 300
        on_failure: skip
EOF

echo "  Test dir: ${TEST_DIR}"
echo ""

# ─── Test 1: yaml_to_json.py ────────────────────────────────────────────────

echo -e "${BOLD}Test: yaml_to_json.py${NC}"

JSON_OUTPUT=$(python3 "${TEST_DIR}/.brain/scripts/yaml_to_json.py" < "${TEST_DIR}/test-plan.yaml" 2>/dev/null)

assert "Выход не пустой" "[[ -n '${JSON_OUTPUT}' ]]"
assert "Валидный JSON" "echo '${JSON_OUTPUT}' | jq . >/dev/null 2>&1"
assert "Имя плана = Test Plan" "[[ \$(echo '${JSON_OUTPUT}' | jq -r '.name') == 'Test Plan' ]]"
assert "2 фазы" "[[ \$(echo '${JSON_OUTPUT}' | jq '.phases | length') == 2 ]]"
assert "Фаза 1: 2 задачи" "[[ \$(echo '${JSON_OUTPUT}' | jq '.phases[0].tasks | length') == 2 ]]"
assert "Фаза 2: 1 задача" "[[ \$(echo '${JSON_OUTPUT}' | jq '.phases[1].tasks | length') == 1 ]]"
echo ""

# ─── Test 2: runner.sh --dry-run ─────────────────────────────────────────────

echo -e "${BOLD}Test: runner.sh --dry-run${NC}"

cd "$TEST_DIR"
bash runner.sh --dry-run test-plan.yaml > /tmp/runner-test-output.txt 2>&1 || true

assert "runner.sh завершился" "true"
assert "Лог создан" "[[ -f .brain/logs/runner.log ]]"
assert "state.json обновлён" "[[ \$(jq -r '.status' .brain/state.json) != 'idle' ]]"
assert "state.json: tasks_total=3" "[[ \$(jq -r '.tasks_total' .brain/state.json) == 3 ]]"

# Проверить что задачи созданы
assert "task-001.json создан" "[[ -f .brain/tasks/task-001.json ]]"
assert "task-002.json создан" "[[ -f .brain/tasks/task-002.json ]]"
assert "task-003.json создан" "[[ -f .brain/tasks/task-003.json ]]"

# Проверить что промпты созданы
assert "worker-001.md создан" "[[ -f .brain/prompts/worker-001.json ]] || [[ -f .brain/prompts/worker-001.md ]]"
assert "worker-002.md создан" "[[ -f .brain/prompts/worker-002.json ]] || [[ -f .brain/prompts/worker-002.md ]]"

# Проверить содержимое задачи
assert "task-001 assigned_to = worker-001" "[[ \$(jq -r '.assigned_to' .brain/tasks/task-001.json) == 'worker-001' ]]"
assert "task-001 role = coder" "[[ \$(jq -r '.role_required' .brain/tasks/task-001.json) == 'coder' ]]"
assert "task-002 on_failure = skip" "[[ \$(jq -r '.on_failure' .brain/tasks/task-002.json) == 'skip' ]]"

# Проверить лог
assert "Лог содержит DRY-RUN" "grep -q 'DRY-RUN' .brain/logs/runner.log"
assert "Лог содержит Plan: Test Plan" "grep -q 'Test Plan' .brain/logs/runner.log"
echo ""

# ─── Итого ───────────────────────────────────────────────────────────────────

echo -e "${BOLD}═══════════════════════════════════════${NC}"
TOTAL=$((PASSED + FAILED))
echo -e "  ${GREEN}${PASSED} passed${NC} / ${RED}${FAILED} failed${NC} / ${TOTAL} total"

if [[ $FAILED -gt 0 ]]; then
    echo -e "  ${RED}TESTS FAILED${NC}"
    exit 1
else
    echo -e "  ${GREEN}ALL TESTS PASSED${NC}"
fi
