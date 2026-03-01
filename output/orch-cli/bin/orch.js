#!/usr/bin/env node
'use strict';

const path = require('node:path');
const { spawn } = require('node:child_process');
const { findBrainRoot, readAll, readWorkers, readTasks, readLog, getLogPath } = require('../src/reader');
const { C: c, formatDashboard, formatWorkers, formatTasks, clearScreen } = require('../src/formatter');

// ────────────── Определение .brain/ ──────────────

const brainDir = findBrainRoot(process.cwd());

if (!brainDir) {
  process.stderr.write(
    `${c.red}Ошибка: директория .brain/ не найдена.${c.reset}\n` +
    `${c.dim}Запускай orch из директории проекта Orchestra (где есть .brain/).${c.reset}\n`
  );
  process.exit(1);
}

// ────────────── Парсинг команд ──────────────

const args = process.argv.slice(2);
const command = args[0] || 'status';

switch (command) {
  case 'status':
    cmdStatus();
    break;
  case 'watch':
    cmdWatch();
    break;
  case 'log':
    cmdLog();
    break;
  case 'tasks':
    cmdTasks();
    break;
  case 'workers':
    cmdWorkers();
    break;
  case 'help':
  case '--help':
  case '-h':
    cmdHelp();
    break;
  default:
    process.stderr.write(`${c.red}Неизвестная команда: ${command}${c.reset}\n\n`);
    cmdHelp();
    process.exit(1);
}

// ────────────── Команды ──────────────

function cmdStatus() {
  const data = readAll(brainDir);
  process.stdout.write(formatDashboard(data) + '\n');
}

function cmdWatch() {
  const INTERVAL = 2000;

  function draw() {
    clearScreen();
    const data = readAll(brainDir);
    process.stdout.write(formatDashboard(data));
    process.stdout.write(`\n ${c.dim}Обновление каждые 2 сек. Ctrl+C для выхода.${c.reset}\n`);
  }

  draw();
  const timer = setInterval(draw, INTERVAL);

  process.on('SIGINT', () => {
    clearInterval(timer);
    process.stdout.write('\n');
    process.exit(0);
  });
}

function cmdLog() {
  const logPath = getLogPath(brainDir);
  const { existsSync } = require('node:fs');

  if (!existsSync(logPath)) {
    process.stderr.write(`${c.red}Лог не найден: ${logPath}${c.reset}\n`);
    process.exit(1);
  }

  const lastLines = readLog(brainDir, 30);
  if (lastLines.trim()) {
    process.stdout.write(lastLines);
    if (!lastLines.endsWith('\n')) process.stdout.write('\n');
  }

  process.stdout.write(`${c.dim}--- tail -f ${path.basename(logPath)} ---${c.reset}\n`);

  const tail = spawn('tail', ['-f', logPath], { stdio: 'inherit' });

  tail.on('error', (err) => {
    process.stderr.write(`${c.red}Не удалось запустить tail: ${err.message}${c.reset}\n`);
    process.exit(1);
  });

  process.on('SIGINT', () => {
    tail.kill();
    process.exit(0);
  });
}

function cmdTasks() {
  const tasks = readTasks(brainDir);
  process.stdout.write(formatTasks(tasks) + '\n');
}

function cmdWorkers() {
  const workers = readWorkers(brainDir);
  process.stdout.write(formatWorkers(workers) + '\n');
}

function cmdHelp() {
  process.stdout.write([
    '',
    ` ${c.bold}${c.cyan}orch${c.reset} ${c.dim}— CLI монитор для Orchestra Brain${c.reset}`,
    '',
    ` ${c.bold}Команды:${c.reset}`,
    `   ${c.cyan}status${c.reset}   Показать статус (по умолчанию)`,
    `   ${c.cyan}watch${c.reset}    Live-мониторинг (обновление каждые 2 сек)`,
    `   ${c.cyan}log${c.reset}      Просмотр лога brain.log (tail -f)`,
    `   ${c.cyan}tasks${c.reset}    Показать задачи`,
    `   ${c.cyan}workers${c.reset}  Показать воркеров`,
    `   ${c.cyan}help${c.reset}     Показать справку`,
    '',
  ].join('\n'));
}
