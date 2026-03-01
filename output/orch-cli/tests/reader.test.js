'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

const { findBrainRoot, readJSON, readState, readWorkers, readTasks, readAll, readLog, getLogPath } = require('../src/reader');

function createTmpBrain() {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'orch-test-'));
  const brainDir = path.join(tmpDir, '.brain');
  fs.mkdirSync(brainDir);
  fs.mkdirSync(path.join(brainDir, 'workers'));
  fs.mkdirSync(path.join(brainDir, 'tasks'));
  fs.mkdirSync(path.join(brainDir, 'logs'));
  return { tmpDir, brainDir };
}

function cleanup(tmpDir) {
  fs.rmSync(tmpDir, { recursive: true, force: true });
}

// --- findBrainRoot ---
describe('findBrainRoot', () => {
  it('находит .brain/ в текущей директории', () => {
    const { tmpDir, brainDir } = createTmpBrain();
    try {
      assert.equal(findBrainRoot(tmpDir), brainDir);
    } finally { cleanup(tmpDir); }
  });

  it('находит .brain/ в родительской директории', () => {
    const { tmpDir, brainDir } = createTmpBrain();
    const subDir = path.join(tmpDir, 'sub', 'deep');
    fs.mkdirSync(subDir, { recursive: true });
    try {
      assert.equal(findBrainRoot(subDir), brainDir);
    } finally { cleanup(tmpDir); }
  });

  it('возвращает null если .brain/ не найден', () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'orch-no-brain-'));
    try {
      assert.equal(findBrainRoot(tmpDir), null);
    } finally { cleanup(tmpDir); }
  });
});

// --- readJSON ---
describe('readJSON', () => {
  it('читает валидный JSON', () => {
    const f = path.join(os.tmpdir(), 'orch-rj-valid.json');
    fs.writeFileSync(f, '{"key":"value"}');
    try { assert.deepEqual(readJSON(f), { key: 'value' }); }
    finally { fs.unlinkSync(f); }
  });

  it('null для несуществующего файла', () => {
    assert.equal(readJSON('/tmp/orch-nonexistent-xyz.json'), null);
  });

  it('null для невалидного JSON', () => {
    const f = path.join(os.tmpdir(), 'orch-rj-invalid.json');
    fs.writeFileSync(f, 'broken{{{');
    try { assert.equal(readJSON(f), null); }
    finally { fs.unlinkSync(f); }
  });
});

// --- readState ---
describe('readState', () => {
  it('читает state.json', () => {
    const { tmpDir, brainDir } = createTmpBrain();
    const data = { status: 'executing', current_phase: 1 };
    fs.writeFileSync(path.join(brainDir, 'state.json'), JSON.stringify(data));
    try { assert.deepEqual(readState(brainDir), data); }
    finally { cleanup(tmpDir); }
  });

  it('null если state.json отсутствует', () => {
    const { tmpDir, brainDir } = createTmpBrain();
    try { assert.equal(readState(brainDir), null); }
    finally { cleanup(tmpDir); }
  });
});

// --- readWorkers ---
describe('readWorkers', () => {
  it('читает и сортирует воркеров по id', () => {
    const { tmpDir, brainDir } = createTmpBrain();
    fs.writeFileSync(path.join(brainDir, 'workers', 'w2.json'), JSON.stringify({ id: 'worker-02' }));
    fs.writeFileSync(path.join(brainDir, 'workers', 'w1.json'), JSON.stringify({ id: 'worker-01' }));
    try {
      const r = readWorkers(brainDir);
      assert.equal(r.length, 2);
      assert.equal(r[0].id, 'worker-01');
      assert.equal(r[1].id, 'worker-02');
    } finally { cleanup(tmpDir); }
  });

  it('пустой массив если нет workers/', () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'orch-nw-'));
    fs.mkdirSync(path.join(tmpDir, '.brain'));
    try { assert.deepEqual(readWorkers(path.join(tmpDir, '.brain')), []); }
    finally { cleanup(tmpDir); }
  });

  it('пропускает невалидные JSON', () => {
    const { tmpDir, brainDir } = createTmpBrain();
    fs.writeFileSync(path.join(brainDir, 'workers', 'ok.json'), JSON.stringify({ id: 'w1' }));
    fs.writeFileSync(path.join(brainDir, 'workers', 'bad.json'), 'broken');
    try {
      const r = readWorkers(brainDir);
      assert.equal(r.length, 1);
    } finally { cleanup(tmpDir); }
  });

  it('игнорирует не-json файлы', () => {
    const { tmpDir, brainDir } = createTmpBrain();
    fs.writeFileSync(path.join(brainDir, 'workers', 'readme.txt'), 'hi');
    try { assert.deepEqual(readWorkers(brainDir), []); }
    finally { cleanup(tmpDir); }
  });
});

// --- readTasks ---
describe('readTasks', () => {
  it('читает и сортирует задачи по id', () => {
    const { tmpDir, brainDir } = createTmpBrain();
    fs.writeFileSync(path.join(brainDir, 'tasks', 't2.json'), JSON.stringify({ id: 'task-002' }));
    fs.writeFileSync(path.join(brainDir, 'tasks', 't1.json'), JSON.stringify({ id: 'task-001' }));
    try {
      const r = readTasks(brainDir);
      assert.equal(r.length, 2);
      assert.equal(r[0].id, 'task-001');
    } finally { cleanup(tmpDir); }
  });

  it('пустой массив если нет tasks/', () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'orch-nt-'));
    fs.mkdirSync(path.join(tmpDir, '.brain'));
    try { assert.deepEqual(readTasks(path.join(tmpDir, '.brain')), []); }
    finally { cleanup(tmpDir); }
  });
});

// --- readAll ---
describe('readAll', () => {
  it('возвращает объект с state, workers, tasks', () => {
    const { tmpDir, brainDir } = createTmpBrain();
    fs.writeFileSync(path.join(brainDir, 'state.json'), JSON.stringify({ status: 'idle' }));
    fs.writeFileSync(path.join(brainDir, 'workers', 'w.json'), JSON.stringify({ id: 'w1' }));
    fs.writeFileSync(path.join(brainDir, 'tasks', 't.json'), JSON.stringify({ id: 't1' }));
    try {
      const r = readAll(brainDir);
      assert.equal(r.state.status, 'idle');
      assert.equal(r.workers.length, 1);
      assert.equal(r.tasks.length, 1);
    } finally { cleanup(tmpDir); }
  });
});

// --- readLog ---
describe('readLog', () => {
  it('читает последние N строк', () => {
    const { tmpDir, brainDir } = createTmpBrain();
    const lines = Array.from({ length: 50 }, (_, i) => 'Line ' + (i + 1));
    fs.writeFileSync(path.join(brainDir, 'logs', 'brain.log'), lines.join('\n'));
    try {
      const r = readLog(brainDir, 5);
      assert.ok(r.includes('Line 50'));
      assert.ok(r.includes('Line 46'));
    } finally { cleanup(tmpDir); }
  });

  it('пустая строка если лога нет', () => {
    const { tmpDir, brainDir } = createTmpBrain();
    try { assert.equal(readLog(brainDir), ''); }
    finally { cleanup(tmpDir); }
  });
});

// --- getLogPath ---
describe('getLogPath', () => {
  it('возвращает путь к brain.log', () => {
    assert.equal(getLogPath('/x/.brain'), path.join('/x/.brain', 'logs', 'brain.log'));
  });
});
