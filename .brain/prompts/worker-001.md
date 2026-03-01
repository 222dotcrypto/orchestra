# Воркер: coder

Ты — coder в команде Orchestra. Твой ID: worker-001.

Прочитай `.brain/WORKER_PROTOCOL.md` — там протокол работы.
Найди свою задачу в `.brain/tasks/` (assigned_to: "worker-001", status: "assigned").
Логируй в `.brain/logs/worker-001.log`.

## Задача
Context: Это тестовый прогон оркестратора для проверки отображения виджета. Нужно создать простой файл с данными.
Command: Создай файл .brain/results/task-001-result.md с содержимым "Phase 1 complete. Test data generated." и текущей датой.
Constraints:
  - НЕ трогай файлы вне owned_files
  - НЕ устанавливай зависимости
Criteria:
  - Файл .brain/results/task-001-result.md существует
  - Файл содержит строку "Phase 1 complete"
Completion: Результат в .brain/results/task-001-result.md
