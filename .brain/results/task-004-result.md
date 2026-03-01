# Результат task-004: CLI entry point + package.json

## Созданные файлы

### output/token-calc/bin/tcalc.js
CLI entry point с shebang. Парсит аргументы через process.argv:
- `tcalc` — отчёт по всем сессиям текущего проекта (только TOTAL)
- `tcalc --breakdown` — детализация по каждой сессии
- `tcalc --since <timestamp>` — фильтр по lastTimestamp
- `tcalc --session <path>` — анализ одного JSONL файла

Алгоритм: findSessions → parseSession → calculateCost → formatReport.

### output/token-calc/package.json
```json
{"name": "tcalc", "version": "1.0.0", "bin": {"tcalc": "bin/tcalc.js"}}
```

## Верификация
- Все 5 acceptance criteria пройдены
- Exit code 0 на всех командах
- Только встроенные модули Node.js
