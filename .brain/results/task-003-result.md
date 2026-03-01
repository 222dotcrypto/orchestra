# Результат task-003: Output formatter module

## Создан файл
`output/token-calc/src/formatter.js`

## Экспортируемые функции

### formatNumber(n)
Форматирует число с разделителями тысяч: `1234567` → `1,234,567`

### formatCost(n)
Форматирует доллары с 2 знаками: `8.42` → `$8.42`

### formatReport(sessions, options)
Принимает массив сессий и `{breakdown: bool}`. Возвращает строку с таблицей:
- Заголовок "Orchestra Token Report"
- Количество сессий и период
- Столбцы: Session, Input, Output, Cache Write, Cache Read, Cost
- При `breakdown=true` — строки по каждой сессии + разделитель + TOTAL
- При `breakdown=false` — только TOTAL
- Пустой массив — сообщение "No sessions found."

## Проверка
Все acceptance criteria выполнены:
- [x] Файл существует
- [x] formatReport возвращает таблицу с заголовком, столбцами, TOTAL
- [x] formatNumber форматирует числа с разделителями тысяч
- [x] formatCost форматирует доллары с 2 знаками
- [x] Только встроенные модули (path)
