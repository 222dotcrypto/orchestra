'use strict';

// ANSI цвета
const C = {
  reset: '\x1b[0m',
  bold: '\x1b[1m',
  dim: '\x1b[2m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  red: '\x1b[31m',
  cyan: '\x1b[36m',
  gray: '\x1b[90m',
  white: '\x1b[37m',
  bgGreen: '\x1b[42m',
  bgYellow: '\x1b[43m',
  bgRed: '\x1b[41m',
  bgGray: '\x1b[100m',
};

function colorForStatus(status) {
  const map = {
    'done': C.green,
    'completed': C.green,
    'active': C.green,
    'executing': C.green,
    'in_progress': C.yellow,
    'busy': C.yellow,
    'assigned': C.yellow,
    'review': C.yellow,
    'planning': C.yellow,
    'failed': C.red,
    'stuck': C.red,
    'dead': C.red,
    'rework': C.red,
    'idle': C.gray,
    'pending': C.gray,
  };
  return map[status] || C.white;
}

function badge(status) {
  const color = colorForStatus(status);
  return `${color}${C.bold} ${status.toUpperCase()} ${C.reset}`;
}

function formatState(state) {
  if (!state) return `${C.red}Ошибка: state.json не найден${C.reset}\n`;

  const lines = [];
  lines.push(`${C.bold}${C.cyan}═══ ORCHESTRA ═══${C.reset}`);
  lines.push('');
  lines.push(`  Статус:  ${badge(state.status)}`);
  if (state.current_task) {
    lines.push(`  Задача:  ${C.white}${state.current_task}${C.reset}`);
  }
  if (state.current_phase) {
    lines.push(`  Фаза:   ${C.white}${state.current_phase}${state.total_phases ? '/' + state.total_phases : ''}${C.reset}`);
  }

  const done = state.tasks_done || 0;
  const total = state.tasks_total || 0;
  const failed = state.tasks_failed || 0;
  const active = state.workers_active || 0;

  lines.push(`  Прогресс: ${C.green}${done}${C.reset}/${total} задач  ${failed > 0 ? C.red + failed + ' failed' + C.reset + '  ' : ''}${C.cyan}${active} воркеров${C.reset}`);

  if (total > 0) {
    const pct = Math.round((done / total) * 100);
    const barLen = 20;
    const filled = Math.round((pct / 100) * barLen);
    const bar = '█'.repeat(filled) + '░'.repeat(barLen - filled);
    lines.push(`  [${C.green}${bar}${C.reset}] ${pct}%`);
  }

  lines.push('');
  return lines.join('\n');
}

function formatWorkers(workers) {
  if (!workers || workers.length === 0) return `${C.gray}  Нет воркеров${C.reset}\n`;

  const lines = [];
  lines.push(`${C.bold}${C.cyan}── Воркеры ──${C.reset}`);
  lines.push('');

  for (const w of workers) {
    const status = w.status || 'unknown';
    const color = colorForStatus(status);
    const icon = status === 'busy' ? '⚙' : status === 'idle' ? '○' : status === 'stuck' ? '✗' : '?';
    const task = w.current_task ? ` → ${C.white}${w.current_task}${C.reset}` : '';
    const role = w.role ? `${C.dim}(${w.role})${C.reset}` : '';
    lines.push(`  ${color}${icon}${C.reset} ${C.bold}${w.id}${C.reset} ${role}  ${badge(status)}${task}`);
  }

  lines.push('');
  return lines.join('\n');
}

function formatTasks(tasks) {
  if (!tasks || tasks.length === 0) return `${C.gray}  Нет задач${C.reset}\n`;

  const lines = [];
  lines.push(`${C.bold}${C.cyan}── Задачи ──${C.reset}`);
  lines.push('');

  for (const t of tasks) {
    const status = t.status || 'unknown';
    const color = colorForStatus(status);
    const icon = status === 'done' ? '✓' : status === 'in_progress' ? '▶' : status === 'review' ? '◎' : status === 'rework' ? '↺' : status === 'failed' ? '✗' : '○';
    const assignee = t.assigned_to ? `${C.dim}→ ${t.assigned_to}${C.reset}` : '';
    const rework = (t.rework_count || 0) > 0 ? ` ${C.red}(rework: ${t.rework_count})${C.reset}` : '';
    lines.push(`  ${color}${icon}${C.reset} ${C.bold}${t.id}${C.reset} ${t.title || ''}  ${badge(status)} ${assignee}${rework}`);
  }

  lines.push('');
  return lines.join('\n');
}

function formatDashboard(data) {
  const lines = [];
  lines.push(formatState(data.state));
  lines.push(formatWorkers(data.workers));
  lines.push(formatTasks(data.tasks));
  lines.push(`${C.dim}  Обновлено: ${new Date().toLocaleTimeString()}${C.reset}`);
  return lines.join('\n');
}

function clearScreen() {
  process.stdout.write('\x1b[2J\x1b[H');
}

// formatStatus — объединённый вывод state + workers + tasks
function formatStatus(state, workers, tasks) {
  return formatDashboard({ state, workers, tasks });
}

// c — алиас для C (для совместимости с bin/orch.js)
const c = C;

module.exports = { C, c, colorForStatus, badge, formatState, formatStatus, formatWorkers, formatTasks, formatDashboard, clearScreen };
