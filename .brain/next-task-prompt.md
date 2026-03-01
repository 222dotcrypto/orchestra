Token cost calculator — CLI-утилита для подсчёта стоимости токенов Orchestra.

Что делает:
- Читает JSONL-файлы сессий из ~/.claude/projects/ (каждая сессия = один JSONL)
- Парсит строки с "type":"assistant" → извлекает message.usage (input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens)
- Считает стоимость по модели: Opus ($15/$75 per 1M input/output), Sonnet ($3/$15), Haiku ($0.80/$4)
- Модель определяет из поля message.model в JSONL

Команды:
- `tcalc` — стоимость текущей директории (все сессии проекта)
- `tcalc --since "2026-03-01T16:00:00Z"` — фильтр по времени (для замера конкретного прогона)
- `tcalc --breakdown` — детализация по сессиям (Мозг vs каждый воркер)
- `tcalc --session <path>` — стоимость конкретного JSONL файла

Вывод:
```
Orchestra Token Report
═══════════════════════
Sessions: 4
Period: 2026-03-01 16:12 → 16:39

  Session                  Input      Output     Cache     Cost
  brain-session.jsonl      125,432    45,210     89,000    $8.42
  worker-01.jsonl          34,521     12,430     28,000    $2.15
  worker-02.jsonl          41,200     15,800     31,000    $2.89
  worker-03.jsonl          22,100     8,900      18,000    $1.54
  ─────────────────────────────────────────────────────────────
  TOTAL                    223,253    82,340     166,000   $15.00
```

Технические требования:
- Node.js, только встроенные модули (fs, path, readline)
- Без зависимостей
- Результат в output/token-calc/
- Структура: bin/tcalc.js, src/parser.js, src/pricing.js, src/formatter.js, package.json
- Тесты в tests/ на node:test

Это второй прогон Orchestra с оптимизациями v2. Цель — сравнить стоимость с первым прогоном ($52). Применяй все оптимизации: сигнальные файлы, adaptive polling, строгие фазы, компактные промпты.
