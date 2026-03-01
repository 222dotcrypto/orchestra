'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { execFile } = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');
const os = require('node:os');

const orchPath = path.resolve(__dirname, '..', 'bin', 'orch.js');

function run(args, cwd) {
  return new Promise((resolve, reject) => {
    execFile(process.execPath, [orchPath, ...args], { cwd, timeout: 5000 }, (err, stdout, stderr) => {
      resolve({ code: err ? err.code : 0, stdout, stderr });
    });
  });
}

// Утилита: создать временную директорию с .brain/
function createTmpProject() {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'orch-cli-test-'));
  const brainDir = path.join(tmpDir, '.brain');
  fs.mkdirSync(brainDir);
  fs.mkdirSync(path.join(brainDir, 'workers'));
  fs.mkdirSync(path.join(brainDir, 'tasks'));
  fs.mkdirSync(path.join(brainDir, 'logs'));

  // state.json
  fs.writeFileSync(path.join(brainDir, 'state.json'), JSON.stringify({
    status: 'executing',
    current_task: 'CLI тест',
    current_phase: 1,
    tasks_done: 1,
    tasks_total: 3,
    tasks_failed: 0,
    workers_active: 2,
  }));

  // worker
  fs.writeFileSync(path.join(brainDir, 'workers', 'worker-01.json'), JSON.stringify({
    id: 'worker-01',
    role: 'coder',
    status: 'busy',
    current_task: 'task-001',
  }));

  // task
  fs.writeFileSync(path.join(brainDir, 'tasks', 'task-001.json'), JSON.stringify({
    id: 'task-001',
    title: 'Написать код',
    status: 'in_progress',
    assigned_to: 'worker-01',
  }));

  // log
  fs.writeFileSync(path.join(brainDir, 'logs', 'brain.log'), '[2026-01-01T00:00:00Z] TEST: log entry\n');

  return tmpDir;
}

function cleanup(tmpDir) {
  fs.rmSync(tmpDir, { recursive: true, force: true });
}

// --- CLI: status (default) ---
describe('CLI status', () => {
  it('выводит дашборд по умолчанию', async () => {
    const tmpDir = createTmpProject();
    try {
      const { code, stdout } = await run([], tmpDir);
      assert.equal(code, 0);
      assert.ok(stdout.includes('ORCHESTRA'));
      assert.ok(stdout.includes('EXECUTING'));
    } finally { cleanup(tmpDir); }
  });

  it('показывает воркеров', async () => {
    const tmpDir = createTmpProject();
    try {
      const { stdout } = await run(['status'], tmpDir);
      assert.ok(stdout.includes('worker-01'));
    } finally { cleanup(tmpDir); }
  });

  it('показывает задачи', async () => {
    const tmpDir = createTmpProject();
    try {
      const { stdout } = await run(['status'], tmpDir);
      assert.ok(stdout.includes('task-001'));
    } finally { cleanup(tmpDir); }
  });
});

// --- CLI: help ---
describe('CLI help', () => {
  it('выводит справку с --help', async () => {
    const tmpDir = createTmpProject();
    try {
      const { code, stdout } = await run(['help'], tmpDir);
      assert.equal(code, 0);
      assert.ok(stdout.includes('status'));
      assert.ok(stdout.includes('watch'));
      assert.ok(stdout.includes('log'));
    } finally { cleanup(tmpDir); }
  });
});

// --- CLI: tasks ---
describe('CLI tasks', () => {
  it('выводит список задач', async () => {
    const tmpDir = createTmpProject();
    try {
      const { code, stdout } = await run(['tasks'], tmpDir);
      assert.equal(code, 0);
      assert.ok(stdout.includes('task-001'));
      assert.ok(stdout.includes('IN_PROGRESS'));
    } finally { cleanup(tmpDir); }
  });
});

// --- CLI: workers ---
describe('CLI workers', () => {
  it('выводит список воркеров', async () => {
    const tmpDir = createTmpProject();
    try {
      const { code, stdout } = await run(['workers'], tmpDir);
      assert.equal(code, 0);
      assert.ok(stdout.includes('worker-01'));
      assert.ok(stdout.includes('BUSY'));
    } finally { cleanup(tmpDir); }
  });
});

// --- CLI: unknown command ---
describe('CLI unknown command', () => {
  it('ошибка при неизвестной команде', async () => {
    const tmpDir = createTmpProject();
    try {
      const { code, stderr } = await run(['foobar'], tmpDir);
      assert.equal(code, 1);
      assert.ok(stderr.includes('foobar'));
    } finally { cleanup(tmpDir); }
  });
});

// --- CLI: no .brain ---
describe('CLI no .brain', () => {
  it('ошибка если нет .brain/', async () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'orch-no-brain-cli-'));
    try {
      const { code, stderr } = await run([], tmpDir);
      assert.equal(code, 1);
      assert.ok(stderr.includes('.brain'));
    } finally { cleanup(tmpDir); }
  });
});
