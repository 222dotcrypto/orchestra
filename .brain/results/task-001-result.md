# Результат task-001: CLI ядро утилиты orch

## Статус: ГОТОВО

## Созданные файлы

```
output/orch-cli/
├── bin/orch.js        — точка входа CLI (executable, shebang)
├── src/reader.js      — чтение state.json, workers/*.json, tasks/*.json
├── src/formatter.js   — ANSI-форматирование с цветами
└── package.json       — name: orch, bin: { orch: bin/orch.js }
```

## Проверка acceptance criteria

| Критерий | Результат |
|---|---|
| `node output/orch-cli/bin/orch.js` выводит статус | ✅ Выводит dashboard: state, workers, tasks с прогресс-баром |
| `node output/orch-cli/bin/orch.js watch` обновляет экран | ✅ Очищает экран + перерисовка каждые 2 сек |
| `node output/orch-cli/bin/orch.js log` запускает tail | ✅ Показывает последние 30 строк + spawn tail -f |
| Нет внешних зависимостей | ✅ Только node:fs, node:path, node:child_process |
| package.json с bin полем | ✅ `"bin": { "orch": "bin/orch.js" }` |

## Дополнительные команды (бонус)

- `orch tasks` — только задачи
- `orch workers` — только воркеры
- `orch help` — справка

## Цвета

- 🟢 Зелёный: done, completed, active, executing
- 🟡 Жёлтый: in_progress, busy, assigned, review, planning
- 🔴 Красный: failed, stuck, dead, rework
- ⚪ Серый: idle, pending

## Установка

```bash
cd output/orch-cli && npm link
# или
node output/orch-cli/bin/orch.js
```
