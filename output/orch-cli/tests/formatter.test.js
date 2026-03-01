'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

const { C, colorForStatus, badge, formatState, formatWorkers, formatTasks, formatDashboard } = require('../src/formatter');

// --- colorForStatus ---
describe('colorForStatus', () => {
  it('зелёный для done', () => {
    assert.equal(colorForStatus('done'), C.green);
  });

  it('зелёный для active', () => {
    assert.equal(colorForStatus('active'), C.green);
  });

  it('жёлтый для in_progress', () => {
    assert.equal(colorForStatus('in_progress'), C.yellow);
  });

  it('жёлтый для busy', () => {
    assert.equal(colorForStatus('busy'), C.yellow);
  });

  it('жёлтый для review', () => {
    assert.equal(colorForStatus('review'), C.yellow);
  });

  it('красный для failed', () => {
    assert.equal(colorForStatus('failed'), C.red);
  });

  it('красный для stuck', () => {
    assert.equal(colorForStatus('stuck'), C.red);
  });

  it('красный для rework', () => {
    assert.equal(colorForStatus('rework'), C.red);
  });

  it('серый для idle', () => {
    assert.equal(colorForStatus('idle'), C.gray);
  });

  it('серый для pending', () => {
    assert.equal(colorForStatus('pending'), C.gray);
  });

  it('белый для неизвестного статуса', () => {
    assert.equal(colorForStatus('unknown_status'), C.white);
  });
});

// --- badge ---
describe('badge', () => {
  it('содержит статус в верхнем регистре', () => {
    const result = badge('done');
    assert.ok(result.includes('DONE'));
  });

  it('содержит ANSI reset в конце', () => {
    const result = badge('idle');
    assert.ok(result.endsWith(C.reset));
  });
});

// --- formatState ---
describe('formatState', () => {
  it('показывает ошибку если state null', () => {
    const result = formatState(null);
    assert.ok(result.includes('state.json не найден'));
  });

  it('содержит заголовок ORCHESTRA', () => {
    const result = formatState({ status: 'executing', tasks_done: 1, tasks_total: 3 });
    assert.ok(result.includes('ORCHESTRA'));
  });

  it('показывает статус', () => {
    const result = formatState({ status: 'executing', tasks_done: 0, tasks_total: 2 });
    assert.ok(result.includes('EXECUTING'));
  });

  it('показывает текущую задачу', () => {
    const result = formatState({ status: 'executing', current_task: 'Мега задача', tasks_done: 0, tasks_total: 1 });
    assert.ok(result.includes('Мега задача'));
  });

  it('показывает фазу', () => {
    const result = formatState({ status: 'executing', current_phase: 2, total_phases: 3, tasks_done: 0, tasks_total: 1 });
    assert.ok(result.includes('2'));
  });

  it('показывает прогресс-бар при наличии задач', () => {
    const result = formatState({ status: 'executing', tasks_done: 1, tasks_total: 2 });
    assert.ok(result.includes('%'));
  });

  it('показывает failed при их наличии', () => {
    const result = formatState({ status: 'executing', tasks_done: 0, tasks_total: 2, tasks_failed: 1 });
    assert.ok(result.includes('failed'));
  });
});

// --- formatWorkers ---
describe('formatWorkers', () => {
  it('показывает "Нет воркеров" при пустом массиве', () => {
    const result = formatWorkers([]);
    assert.ok(result.includes('Нет воркеров'));
  });

  it('null → "Нет воркеров"', () => {
    const result = formatWorkers(null);
    assert.ok(result.includes('Нет воркеров'));
  });

  it('содержит id воркера', () => {
    const result = formatWorkers([{ id: 'worker-01', status: 'busy', role: 'coder' }]);
    assert.ok(result.includes('worker-01'));
  });

  it('содержит роль воркера', () => {
    const result = formatWorkers([{ id: 'worker-01', status: 'idle', role: 'tester' }]);
    assert.ok(result.includes('tester'));
  });

  it('содержит текущую задачу', () => {
    const result = formatWorkers([{ id: 'w1', status: 'busy', current_task: 'task-005' }]);
    assert.ok(result.includes('task-005'));
  });
});

// --- formatTasks ---
describe('formatTasks', () => {
  it('показывает "Нет задач" при пустом массиве', () => {
    const result = formatTasks([]);
    assert.ok(result.includes('Нет задач'));
  });

  it('null → "Нет задач"', () => {
    const result = formatTasks(null);
    assert.ok(result.includes('Нет задач'));
  });

  it('содержит id задачи', () => {
    const result = formatTasks([{ id: 'task-001', title: 'Тест', status: 'done' }]);
    assert.ok(result.includes('task-001'));
  });

  it('содержит title задачи', () => {
    const result = formatTasks([{ id: 't1', title: 'Моя задача', status: 'in_progress' }]);
    assert.ok(result.includes('Моя задача'));
  });

  it('содержит assigned_to', () => {
    const result = formatTasks([{ id: 't1', status: 'assigned', assigned_to: 'worker-03' }]);
    assert.ok(result.includes('worker-03'));
  });

  it('показывает rework_count', () => {
    const result = formatTasks([{ id: 't1', status: 'rework', rework_count: 2 }]);
    assert.ok(result.includes('rework: 2'));
  });
});

// --- formatDashboard ---
describe('formatDashboard', () => {
  it('объединяет state + workers + tasks', () => {
    const data = {
      state: { status: 'executing', tasks_done: 1, tasks_total: 2 },
      workers: [{ id: 'w1', status: 'busy', role: 'coder' }],
      tasks: [{ id: 't1', title: 'Task', status: 'done' }],
    };
    const result = formatDashboard(data);
    assert.ok(result.includes('ORCHESTRA'));
    assert.ok(result.includes('w1'));
    assert.ok(result.includes('t1'));
  });

  it('содержит время обновления', () => {
    const data = { state: { status: 'idle' }, workers: [], tasks: [] };
    const result = formatDashboard(data);
    assert.ok(result.includes('Обновлено'));
  });
});
