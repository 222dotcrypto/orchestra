# Orchestra — AI-оркестратор на Claude Code + tmux

Система где один Claude Code (Мозг) управляет командой воркеров (другие Claude Code процессы) через tmux.

## Зависимости

```bash
# Claude Code (должен быть установлен и авторизован)
claude --version

# tmux
brew install tmux  # macOS
# или: apt install tmux  # Linux

# jq (для работы с JSON в скриптах)
brew install jq    # macOS
# или: apt install jq    # Linux
```

## Быстрый старт

### 1. Перейди в директорию

```bash
cd orchestra
```

### 2. Запусти Мозг

```bash
claude
```

Claude Code подхватит `CLAUDE.md` автоматически — это system prompt Мозга.

### 3. Дай задачу

Просто напиши что нужно сделать:

```
Создай REST API на FastAPI с эндпоинтами /users и /posts, напиши тесты на pytest, сделай Dockerfile.
```

Мозг сам:
- Составит план
- Определит роли (coder, tester, devops)
- Запустит воркеров в отдельных tmux окнах
- Назначит задачи
- Проверит результаты
- Соберёт финальный результат в `output/`

### 4. Мониторинг

В **другом** терминале:

```bash
# Разовый снимок статуса
cd orchestra && bash .brain/scripts/monitor.sh

# Автообновление каждые 5 сек
cd orchestra && bash .brain/scripts/monitor.sh --watch
```

Или через tmux:
```bash
# Подключиться к сессии
tmux attach -t orchestra

# Переключение между окнами: Ctrl+B, затем номер окна
# Список окон: Ctrl+B, W
```

## Структура

```
orchestra/
├── CLAUDE.md                  ← System prompt Мозга
├── README.md                  ← Этот файл
├── output/                    ← Финальные результаты
└── .brain/
    ├── plan.md                ← План текущей задачи
    ├── state.json             ← Состояние оркестратора
    ├── tasks/                 ← JSON-файлы задач для воркеров
    ├── workers/               ← JSON-файлы состояния воркеров
    ├── results/               ← Результаты выполненных задач
    │   └── content/           ← Контент от content_analyst
    ├── prompts/               ← Сгенерированные промпты воркеров
    ├── logs/                  ← Логи мозга и воркеров
    ├── scripts/               ← Bash-скрипты управления
    │   ├── spawn-worker.sh    ← Запуск воркера в tmux
    │   ├── kill-worker.sh     ← Остановка воркера
    │   └── monitor.sh         ← Статус системы
    └── inbox/                 ← Материалы для контент-анализа
```

## Скрипты управления

### Запуск воркера вручную

```bash
bash .brain/scripts/spawn-worker.sh worker-01 coder
```

### Остановка воркера

```bash
bash .brain/scripts/kill-worker.sh worker-01
bash .brain/scripts/kill-worker.sh --all  # убить всех
```

### Монитор

```bash
bash .brain/scripts/monitor.sh          # разовый снимок
bash .brain/scripts/monitor.sh --watch  # автообновление
```

## Контент-пайплайн

Для анализа материалов (экспортированные чаты, логи, заметки):

1. Положи файлы в `.brain/inbox/`
2. Скажи Мозгу: "Проанализируй материалы из inbox и создай [посты / гайд / тред]"
3. Результаты появятся в `.brain/results/content/`

## Протокол общения

Мозг и воркеры общаются через файлы:
- **Задачи**: `.brain/tasks/task-{id}.json` — Мозг создаёт, воркеры читают и обновляют статус
- **Статус воркеров**: `.brain/workers/worker-{id}.json` — воркеры обновляют heartbeat
- **Результаты**: `.brain/results/` — воркеры пишут, Мозг проверяет
- **Логи**: `.brain/logs/` — все пишут

## Очистка

После завершения задачи можно очистить рабочие файлы:

```bash
rm -rf .brain/tasks/*.json .brain/workers/*.json .brain/results/*.md .brain/prompts/*.md .brain/logs/*.log
```

## Решение проблем

**Воркер не запускается**: проверь что промпт существует в `.brain/prompts/`

**tmux сессия не найдена**: скрипт создаст её автоматически при первом spawn

**Воркер завис**: `bash .brain/scripts/kill-worker.sh worker-XX` и перезапусти

**Мозг не видит результатов**: проверь что воркер записал результат в правильный `result_path`
