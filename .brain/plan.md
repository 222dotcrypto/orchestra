# План: CLI-утилита `orch` — мониторинг оркестратора из терминала

## Описание
Node.js CLI без зависимостей. Читает `.brain/` и выводит статус в терминал.
Результат: `output/orch-cli/`

## Фазы

### Фаза 1: Разработка (параллельно)
- task-001: CLI ядро → worker-01 (coder)
- task-002: Тесты → worker-02 (tester)
- task-003: README → worker-03 (writer)

## Воркеры
- worker-01: coder — bin/orch.js, src/reader.js, src/formatter.js, package.json
- worker-02: tester — tests/
- worker-03: writer — README.md

## Критерии готовности
- [ ] `node output/orch-cli/bin/orch.js` выводит статус
- [ ] `node output/orch-cli/bin/orch.js watch` обновляет каждые 2 сек
- [ ] `node output/orch-cli/bin/orch.js log` tail логов
- [ ] Тесты проходят
- [ ] README описывает использование
