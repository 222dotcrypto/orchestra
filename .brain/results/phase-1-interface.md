# Интерфейсы модулей Фазы 1

## src/parser.js
```js
const { findSessions, parseSession } = require('./src/parser');
// findSessions(projectDir: string) → string[] (абсолютные пути к .jsonl файлам)
// parseSession(filePath: string) → Promise<{filename, model, totalInput, totalOutput, totalCacheCreation, totalCacheRead, firstTimestamp, lastTimestamp}>
```

## src/pricing.js
```js
const { PRICING, calculateCost } = require('./src/pricing');
// calculateCost(model: string, usage: {input, output, cacheCreation, cacheRead}) → {inputCost, outputCost, cacheCreationCost, cacheReadCost, totalCost}
```

## src/formatter.js
```js
const { formatReport, formatNumber, formatCost } = require('./src/formatter');
// formatReport(sessions: Array<{filename, totalInput, totalOutput, totalCacheCreation, totalCacheRead, cost:{totalCost}, firstTimestamp, lastTimestamp}>, options: {breakdown: bool}) → string
// formatNumber(n) → string (1234567 → "1,234,567")
// formatCost(n) → string (1.23 → "$1.23")
```
