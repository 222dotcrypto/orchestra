# Результат task-005: Unit tests for all modules

## Статус: PASS

## Файлы тестов
1. `output/token-calc/tests/parser.test.js` — 11 тестов (findSessions: 5, parseSession: 6)
2. `output/token-calc/tests/pricing.test.js` — 15 тестов (PRICING: 3, calculateCost: 12)
3. `output/token-calc/tests/formatter.test.js` — 26 тестов (formatNumber: 9, formatCost: 8, formatReport: 9)

## Покрытие

### parser.js
- `findSessions`: сортировка, абсолютные пути, фильтрация .jsonl, несуществующая директория, пустая директория
- `parseSession`: суммирование токенов, пустой файл (нули), игнорирование не-assistant записей, timestamps (min/max), malformed JSON, запись без usage

### pricing.js
- `PRICING`: наличие моделей, корректные цены
- `calculateCost`: opus input/output, sonnet input/output, cache costs, total, fallback по substring (opus, haiku), fallback на sonnet для неизвестной модели, нулевой usage, пустой usage, дробные значения

### formatter.js
- `formatNumber`: числа с запятыми, 0, без запятых <1000, большие числа, null/undefined/NaN, округление float
- `formatCost`: $X.XX формат, 0, null/undefined/NaN, округление
- `formatReport`: пустой/null/undefined → "No sessions found", заголовок, TOTAL, session count, суммирование, breakdown с именами, missing cost

## Зависимости
Только `node:test` и `node:assert/strict` — без внешних зависимостей.

## Полный вывод тестов

```
# tests 52
# suites 7
# pass 52
# fail 0
# cancelled 0
# skipped 0
# todo 0
# duration_ms 95.097625
```

Все 52 теста пройдены.
