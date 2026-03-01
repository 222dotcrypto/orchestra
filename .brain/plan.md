# План: Token Cost Calculator (tcalc)
Класс: moderate

## Цель
CLI-утилита для подсчёта стоимости токенов Orchestra по JSONL-файлам сессий.

## Фазы

### Фаза 1: Core модули (параллельно)
- task-001: src/parser.js → worker-01 (coder)
- task-002: src/pricing.js → worker-02 (coder)
- task-003: src/formatter.js → worker-03 (coder)

### Фаза 2: Интеграция + тесты (параллельно)
- task-004: bin/tcalc.js + package.json → worker-04 (coder)
- task-005: tests/ → worker-05 (tester)

## DAG
task-001,002,003 → task-004,005

## Критерии готовности
- [ ] tcalc показывает отчёт
- [ ] --since, --breakdown, --session работают
- [ ] Тесты проходят
- [ ] Только встроенные модули Node.js
