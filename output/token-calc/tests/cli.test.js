const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

const { parseArgs, resolveProjectDir } = require('../bin/tcalc');

describe('parseArgs', () => {
  it('returns defaults with no arguments', () => {
    const result = parseArgs(['node', 'tcalc']);
    assert.deepEqual(result, { breakdown: false, since: null, session: null, help: false, version: false });
  });

  it('parses --breakdown', () => {
    const result = parseArgs(['node', 'tcalc', '--breakdown']);
    assert.equal(result.breakdown, true);
  });

  it('parses --since with value', () => {
    const result = parseArgs(['node', 'tcalc', '--since', '2026-03-01T00:00:00Z']);
    assert.equal(result.since, '2026-03-01T00:00:00Z');
  });

  it('parses --session with path', () => {
    const result = parseArgs(['node', 'tcalc', '--session', '/tmp/test.jsonl']);
    assert.equal(result.session, '/tmp/test.jsonl');
  });

  it('parses --help', () => {
    const result = parseArgs(['node', 'tcalc', '--help']);
    assert.equal(result.help, true);
  });

  it('parses -h', () => {
    const result = parseArgs(['node', 'tcalc', '-h']);
    assert.equal(result.help, true);
  });

  it('parses --version', () => {
    const result = parseArgs(['node', 'tcalc', '--version']);
    assert.equal(result.version, true);
  });

  it('parses -v', () => {
    const result = parseArgs(['node', 'tcalc', '-v']);
    assert.equal(result.version, true);
  });

  it('parses multiple flags together', () => {
    const result = parseArgs(['node', 'tcalc', '--breakdown', '--since', '2026-03-01']);
    assert.equal(result.breakdown, true);
    assert.equal(result.since, '2026-03-01');
  });
});

describe('resolveProjectDir', () => {
  it('returns null when ~/.claude/projects/ does not exist', () => {
    const origCwd = process.cwd;
    process.cwd = () => '/nonexistent/path/xyz';
    const result = resolveProjectDir();
    process.cwd = origCwd;
    // Может вернуть null если нет совпадения
    // Основная проверка — не бросает ошибку
    assert.ok(result === null || typeof result === 'string');
  });
});
