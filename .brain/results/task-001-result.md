# Результат task-001: JSONL parser module

## Создан файл
`output/token-calc/src/parser.js`

## Экспорт
- `findSessions(projectDir)` — возвращает массив абсолютных путей к .jsonl файлам
- `parseSession(filePath)` — async, читает JSONL через readline, возвращает объект с полями: filename, model, totalInput, totalOutput, totalCacheCreation, totalCacheRead, firstTimestamp, lastTimestamp

## Верификация
- findSessions: корректно фильтрует .jsonl, возвращает абсолютные пути
- parseSession: правильно суммирует токены, игнорирует не-assistant строки, пропускает невалидный JSON и строки без usage
- Только встроенные модули: fs, path, readline
