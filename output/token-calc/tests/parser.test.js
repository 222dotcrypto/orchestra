const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const os = require('os');

const { findSessions, parseSession } = require('../src/parser');

describe('findSessions', () => {
  let tmpDir;

  before(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'tcalc-parser-'));
    // Создаём файлы с разницей в mtime чтобы сортировка была предсказуемой
    fs.writeFileSync(path.join(tmpDir, 'session-b.jsonl'), '');
    const pastTime = new Date(Date.now() - 10000);
    fs.utimesSync(path.join(tmpDir, 'session-b.jsonl'), pastTime, pastTime);
    fs.writeFileSync(path.join(tmpDir, 'session-a.jsonl'), '');
    fs.writeFileSync(path.join(tmpDir, 'readme.txt'), '');
    fs.writeFileSync(path.join(tmpDir, 'data.json'), '');
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it('returns array of .jsonl file paths sorted by mtime', () => {
    const result = findSessions(tmpDir);
    assert.equal(result.length, 2);
    // session-b создан раньше (pastTime), session-a позже
    assert.ok(result[0].endsWith('session-b.jsonl'));
    assert.ok(result[1].endsWith('session-a.jsonl'));
  });

  it('returns absolute paths', () => {
    const result = findSessions(tmpDir);
    for (const p of result) {
      assert.ok(path.isAbsolute(p), `path should be absolute: ${p}`);
    }
  });

  it('returns empty array for non-existent directory', () => {
    const result = findSessions('/tmp/nonexistent-dir-tcalc-test-xyz');
    assert.deepEqual(result, []);
  });

  it('returns empty array for directory with no .jsonl files', () => {
    const emptyDir = fs.mkdtempSync(path.join(os.tmpdir(), 'tcalc-empty-'));
    fs.writeFileSync(path.join(emptyDir, 'file.txt'), '');
    const result = findSessions(emptyDir);
    assert.deepEqual(result, []);
    fs.rmSync(emptyDir, { recursive: true, force: true });
  });

  it('filters out non-.jsonl files', () => {
    const result = findSessions(tmpDir);
    for (const p of result) {
      assert.ok(p.endsWith('.jsonl'), `should end with .jsonl: ${p}`);
    }
  });
});

describe('parseSession', () => {
  let tmpDir;

  before(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'tcalc-parse-'));
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it('parses assistant entries and sums tokens correctly', async () => {
    const lines = [
      JSON.stringify({
        type: 'assistant',
        message: {
          model: 'claude-opus-4-6',
          usage: {
            input_tokens: 100,
            output_tokens: 50,
            cache_creation_input_tokens: 200,
            cache_read_input_tokens: 300,
          },
        },
        timestamp: '2026-03-01T10:00:00Z',
      }),
      JSON.stringify({
        type: 'assistant',
        message: {
          model: 'claude-opus-4-6',
          usage: {
            input_tokens: 400,
            output_tokens: 150,
            cache_creation_input_tokens: 0,
            cache_read_input_tokens: 100,
          },
        },
        timestamp: '2026-03-01T11:00:00Z',
      }),
    ];

    const filePath = path.join(tmpDir, 'session-sum.jsonl');
    fs.writeFileSync(filePath, lines.join('\n'));

    const result = await parseSession(filePath);
    assert.equal(result.totalInput, 500);
    assert.equal(result.totalOutput, 200);
    assert.equal(result.totalCacheCreation, 200);
    assert.equal(result.totalCacheRead, 400);
    assert.equal(result.model, 'claude-opus-4-6');
    assert.equal(result.filename, 'session-sum.jsonl');
  });

  it('returns zeros for empty file', async () => {
    const filePath = path.join(tmpDir, 'empty.jsonl');
    fs.writeFileSync(filePath, '');

    const result = await parseSession(filePath);
    assert.equal(result.totalInput, 0);
    assert.equal(result.totalOutput, 0);
    assert.equal(result.totalCacheCreation, 0);
    assert.equal(result.totalCacheRead, 0);
    assert.equal(result.model, null);
    assert.equal(result.firstTimestamp, null);
    assert.equal(result.lastTimestamp, null);
  });

  it('ignores non-assistant entries', async () => {
    const lines = [
      JSON.stringify({
        type: 'human',
        message: { usage: { input_tokens: 9999, output_tokens: 9999 } },
        timestamp: '2026-03-01T10:00:00Z',
      }),
      JSON.stringify({
        type: 'system',
        message: { usage: { input_tokens: 5555 } },
      }),
      JSON.stringify({
        type: 'assistant',
        message: {
          model: 'claude-sonnet-4-6',
          usage: { input_tokens: 10, output_tokens: 20 },
        },
        timestamp: '2026-03-01T12:00:00Z',
      }),
    ];

    const filePath = path.join(tmpDir, 'mixed.jsonl');
    fs.writeFileSync(filePath, lines.join('\n'));

    const result = await parseSession(filePath);
    assert.equal(result.totalInput, 10);
    assert.equal(result.totalOutput, 20);
    assert.equal(result.model, 'claude-sonnet-4-6');
  });

  it('tracks first and last timestamps correctly', async () => {
    const lines = [
      JSON.stringify({
        type: 'assistant',
        message: { model: 'claude-opus-4-6', usage: { input_tokens: 1 } },
        timestamp: '2026-03-01T12:00:00Z',
      }),
      JSON.stringify({
        type: 'assistant',
        message: { model: 'claude-opus-4-6', usage: { input_tokens: 1 } },
        timestamp: '2026-03-01T08:00:00Z',
      }),
      JSON.stringify({
        type: 'assistant',
        message: { model: 'claude-opus-4-6', usage: { input_tokens: 1 } },
        timestamp: '2026-03-01T16:00:00Z',
      }),
    ];

    const filePath = path.join(tmpDir, 'timestamps.jsonl');
    fs.writeFileSync(filePath, lines.join('\n'));

    const result = await parseSession(filePath);
    assert.equal(result.firstTimestamp, '2026-03-01T08:00:00Z');
    assert.equal(result.lastTimestamp, '2026-03-01T16:00:00Z');
  });

  it('skips malformed JSON lines gracefully', async () => {
    const lines = [
      'this is not json',
      '{broken json',
      JSON.stringify({
        type: 'assistant',
        message: {
          model: 'claude-opus-4-6',
          usage: { input_tokens: 42, output_tokens: 7 },
        },
        timestamp: '2026-03-01T10:00:00Z',
      }),
    ];

    const filePath = path.join(tmpDir, 'malformed.jsonl');
    fs.writeFileSync(filePath, lines.join('\n'));

    const result = await parseSession(filePath);
    assert.equal(result.totalInput, 42);
    assert.equal(result.totalOutput, 7);
  });

  it('throws on non-existent file', async () => {
    await assert.rejects(
      () => parseSession('/tmp/nonexistent-tcalc-test-file.jsonl'),
      { message: /Не удалось прочитать файл/ }
    );
  });

  it('handles assistant entry without usage gracefully', async () => {
    const lines = [
      JSON.stringify({
        type: 'assistant',
        message: { model: 'claude-opus-4-6' },
        timestamp: '2026-03-01T10:00:00Z',
      }),
      JSON.stringify({
        type: 'assistant',
        message: {
          model: 'claude-opus-4-6',
          usage: { input_tokens: 5 },
        },
        timestamp: '2026-03-01T11:00:00Z',
      }),
    ];

    const filePath = path.join(tmpDir, 'no-usage.jsonl');
    fs.writeFileSync(filePath, lines.join('\n'));

    const result = await parseSession(filePath);
    assert.equal(result.totalInput, 5);
    assert.equal(result.totalOutput, 0);
  });
});
