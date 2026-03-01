Запусти параллельный code review текущей работы.

## Алгоритм

### 1. Определи изменённые файлы

Выполни `git diff --name-status HEAD` и `git diff --name-status --cached` чтобы найти все изменённые и новые файлы.
Если git не инициализирован — используй `find . -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.sh' -o -name '*.md' -newer .brain/state.json` для поиска недавно изменённых файлов.
Исключи из проверки: node_modules, .brain/logs, .brain/metrics.jsonl, __pycache__, .git.

Если передан аргумент `$ARGUMENTS` и он содержит "full" — собери ВСЕ файлы проекта (кроме исключений выше) для полной проверки.

### 2. Сформируй review-request

Создай файл `.brain/review/requests/review-request-{timestamp}.md` с таким форматом:

```markdown
# Review Request — {дата и время}

## Режим: partial / full

## Описание
{Краткое описание что было сделано — 1-2 предложения на основе git diff или контекста сессии}

## Файлы для проверки
- path/to/file1.py (новый / изменён)
- path/to/file2.js (новый / изменён)

## Контекст
{Если есть .brain/plan.md — укажи текущую фазу и цель. Если нет — пропусти}
```

Timestamp формат: `YYYYMMDD-HHMMSS` (через `date +%Y%m%d-%H%M%S`).

### 3. Запусти ревьюера

```bash
bash .brain/scripts/spawn-reviewer.sh .brain/review/requests/review-request-{timestamp}.md
```

### 4. Сообщи результат

Напиши пользователю:
- Ревьюер запущен в tmux окне `orchestra:reviewer`
- Количество файлов на проверке
- Результат будет в `.brain/review/results/`
- Для проверки результата: `/review-check`

Продолжай свою работу. НЕ жди завершения ревьюера.
