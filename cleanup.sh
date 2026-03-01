#!/bin/bash
# cleanup.sh — Удаление артефактов прогонов и несвязанных файлов
# Запусти вручную: bash cleanup.sh
# После запуска: git add -A && git commit

set -euo pipefail

echo "=== Удаление артефактов прогонов ==="

# Задачи прогонов
git rm -f .brain/tasks/task-*.json 2>/dev/null || true

# Результаты прогонов
git rm -f .brain/results/task-*-result.md 2>/dev/null || true
git rm -f .brain/results/audit-report.md 2>/dev/null || true
git rm -f .brain/results/v1-vs-v2-comparison.md 2>/dev/null || true
git rm -f .brain/results/phase-1-interface.md 2>/dev/null || true
git rm -rf .brain/results/content/ 2>/dev/null || true

# Сгенерированные промпты (оставляем templates/)
git rm -f .brain/prompts/worker-*.md 2>/dev/null || true

# Runtime файлы
git rm -f .brain/plan.md 2>/dev/null || true
git rm -f .brain/session-notes.md 2>/dev/null || true
git rm -f .brain/session-analysis.md 2>/dev/null || true
git rm -f .brain/audit-prompt.md 2>/dev/null || true
git rm -f .brain/next-task-prompt.md 2>/dev/null || true

echo "=== Удаление несвязанных инструментов ==="

# system/ (changelog + skill-indexer)
git rm -rf system/ 2>/dev/null || true

# skills/context-builder/ и empty-skill/
git rm -rf skills/context-builder/ 2>/dev/null || true
git rm -rf skills/empty-skill/ 2>/dev/null || true

# output/ (продукты прогонов)
git rm -rf output/ 2>/dev/null || true

echo "=== Удаление user-specific файлов ==="
git rm -f .claude/settings.local.json 2>/dev/null || true

echo "=== Готово ==="
echo "Запусти: git status"
echo "Затем:   git add -A && git commit -m 'chore: clean up for public release'"
