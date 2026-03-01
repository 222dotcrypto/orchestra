# orch

CLI-монитор для **Orchestra** — системы оркестрации AI-воркеров через tmux.

Показывает состояние системы, воркеров и задач в реальном времени с цветным выводом в терминале.

## Установка

```bash
cd output/orch-cli
npm link
```

После этого команда `orch` доступна глобально. Запускать из любой директории внутри проекта Orchestra (утилита сама найдёт `.brain/`).

**Требования:** Node.js >= 18. Внешних зависимостей нет.

## Команды

### `orch`

Однократный вывод текущего статуса: состояние оркестратора, список воркеров и задач.

```
═══ ORCHESTRA ═══

  Статус:   EXECUTING
  Задача:   Создать CLI-утилиту orch
  Фаза:     1/2
  Прогресс: 1/3 задач  2 воркеров
  [██████░░░░░░░░░░░░░░] 33%

── Воркеры ──

  ⚙ worker-01 (coder)   BUSY  → task-001
  ⚙ worker-02 (tester)  BUSY  → task-002
  ○ worker-03 (writer)   IDLE

── Задачи ──

  ✓ task-001 CLI ядро утилиты orch   DONE    → worker-01
  ▶ task-002 Тесты для CLI orch      IN_PROGRESS → worker-02
  ○ task-003 README для CLI orch     PENDING → worker-03

  Обновлено: 16:18:30
```

**Иконки задач:** ✓ done, ▶ in_progress, ◎ review, ↺ rework, ✗ failed, ○ pending

**Иконки воркеров:** ⚙ busy, ○ idle, ✗ stuck

**Цвета:** зелёный — done/active, жёлтый — in_progress/busy/review, красный — failed/stuck/rework, серый — idle/pending.

### `orch watch`

Live-режим: обновляет экран каждые 2 секунды. Выход — `Ctrl+C`.

```bash
orch watch
```

Удобно держать в отдельном окне терминала или tmux-панели для мониторинга в реальном времени.

### `orch log`

Потоковый вывод лога Мозга (`tail -f .brain/logs/brain.log`). Выход — `Ctrl+C`.

```bash
orch log
```

```
[2026-02-28T16:00:00Z] CLASSIFY: "Создать CLI" → moderate
[2026-02-28T16:00:05Z] SPAWN: worker-01 (coder)
[2026-02-28T16:05:30Z] ACCEPT: task-001
[2026-02-28T16:10:00Z] DONE: Результат в output/
```

### `orch help`

Справка по командам.

```bash
orch help
```

## Структура проекта

```
output/orch-cli/
├── bin/
│   └── orch.js          # Точка входа, парсинг команд
├── src/
│   ├── reader.js        # Чтение state.json, workers/*.json, tasks/*.json
│   └── formatter.js     # Форматирование с ANSI-цветами
├── package.json
└── README.md
```

**bin/orch.js** — точка входа. Определяет команду из аргументов (`status` по умолчанию), ищет `.brain/` вверх по дереву директорий.

**src/reader.js** — чтение данных: `findBrainRoot()` ищет `.brain/` от текущей директории вверх; `readAll()` возвращает state, workers и tasks.

**src/formatter.js** — ANSI-форматирование: прогресс-бар, цветные бейджи статусов, иконки для воркеров и задач.
