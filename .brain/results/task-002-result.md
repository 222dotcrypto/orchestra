# Результат: task-002 — Token pricing module

## Создан файл
`output/token-calc/src/pricing.js`

## Что реализовано
1. **PRICING** — объект с ценами за 1M токенов для 3 моделей (opus, sonnet, haiku)
2. **calculateCost(model, usage)** — расчёт стоимости, возвращает {inputCost, outputCost, cacheCreationCost, cacheReadCost, totalCost}
3. **Fallback** — поиск по подстроке (opus/sonnet/haiku), если точного совпадения нет. Для полностью неизвестных моделей — цены Sonnet

## Проверка acceptance criteria
- [x] Файл output/token-calc/src/pricing.js существует
- [x] PRICING содержит цены для opus, sonnet, haiku
- [x] calculateCost возвращает объект с inputCost, outputCost, cacheCreationCost, cacheReadCost, totalCost
- [x] Fallback для неизвестных моделей работает (подстрока + default)
