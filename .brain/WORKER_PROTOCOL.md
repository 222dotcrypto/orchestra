# Протокол воркера Orchestra

## Начало работы
1. Прочитай `.brain/tasks/` — найди задачу с `"assigned_to": "{WORKER_ID}"` и `"status": "assigned"`
2. Обнови задачу: `"status": "in_progress"`
3. Обнови `.brain/workers/{WORKER_ID}.json`: `"status": "busy"`, `"current_task": "task-XXX"`

## Выполнение
- Прочитай `description` задачи — там КОНТЕКСТ, ЗАДАЧА, ОГРАНИЧЕНИЯ
- Прочитай `acceptance_criteria` — это чек-лист готовности
- Меняй ТОЛЬКО файлы из `owned_files`
- Результат запиши в файл из `result_path`

## Завершение
1. Обнови задачу: `"status": "review"`
2. Обнови себя: `"status": "idle"`, `"current_task": null`
3. Создай сигнальный файл:
```bash
touch .brain/signals/{TASK_ID}.review
```

## Rework
Если задача вернулась со `"status": "rework"`:
1. Прочитай `"rework_comment"` — там конкретное замечание
2. Исправь результат
3. Снова `"status": "review"` + `touch .brain/signals/{TASK_ID}.review`

## Правила
- НЕ трогай файлы вне `owned_files`
- НЕ меняй чужие задачи
- Результат ТОЛЬКО в свой `result_path`
- Если застрял — статус `"stuck"`, опиши проблему в `.brain/logs/{WORKER_ID}.log`
- Атомарные записи JSON: write → `/tmp/file.tmp` → `mv` в целевой путь
