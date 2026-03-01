const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

const { formatNumber, formatCost, formatReport, formatTimestamp } = require('../src/formatter');

describe('formatNumber', () => {
  it('formats 1234567 as "1,234,567"', () => {
    assert.equal(formatNumber(1234567), '1,234,567');
  });

  it('formats 0 as "0"', () => {
    assert.equal(formatNumber(0), '0');
  });

  it('formats 999 without commas', () => {
    assert.equal(formatNumber(999), '999');
  });

  it('formats 1000 as "1,000"', () => {
    assert.equal(formatNumber(1000), '1,000');
  });

  it('formats large number correctly', () => {
    assert.equal(formatNumber(1000000000), '1,000,000,000');
  });

  it('handles null as "0"', () => {
    assert.equal(formatNumber(null), '0');
  });

  it('handles undefined as "0"', () => {
    assert.equal(formatNumber(undefined), '0');
  });

  it('handles NaN as "0"', () => {
    assert.equal(formatNumber(NaN), '0');
  });

  it('rounds floating point', () => {
    assert.equal(formatNumber(1234.7), '1,235');
  });
});

describe('formatCost', () => {
  it('formats 1.5 as "$1.50"', () => {
    assert.equal(formatCost(1.5), '$1.50');
  });

  it('formats 0 as "$0.00"', () => {
    assert.equal(formatCost(0), '$0.00');
  });

  it('formats 110.25 as "$110.25"', () => {
    assert.equal(formatCost(110.25), '$110.25');
  });

  it('formats small cost with two decimals', () => {
    assert.equal(formatCost(0.003), '$0.00');
  });

  it('handles null as "$0.00"', () => {
    assert.equal(formatCost(null), '$0.00');
  });

  it('handles undefined as "$0.00"', () => {
    assert.equal(formatCost(undefined), '$0.00');
  });

  it('handles NaN as "$0.00"', () => {
    assert.equal(formatCost(NaN), '$0.00');
  });

  it('formats precise value', () => {
    assert.equal(formatCost(99.999), '$100.00');
  });
});

describe('formatReport', () => {
  it('returns "No sessions found" for empty array', () => {
    const report = formatReport([]);
    assert.ok(report.includes('No sessions found'));
    assert.ok(report.includes('Orchestra Token Report'));
  });

  it('returns "No sessions found" for null', () => {
    const report = formatReport(null);
    assert.ok(report.includes('No sessions found'));
  });

  it('returns "No sessions found" for undefined', () => {
    const report = formatReport(undefined);
    assert.ok(report.includes('No sessions found'));
  });

  it('contains "Orchestra Token Report" header with data', () => {
    const sessions = [
      {
        filename: 'session.jsonl',
        totalInput: 1000,
        totalOutput: 500,
        totalCacheCreation: 200,
        totalCacheRead: 100,
        cost: { totalCost: 0.05 },
        firstTimestamp: '2026-03-01T10:00:00Z',
        lastTimestamp: '2026-03-01T11:00:00Z',
      },
    ];
    const report = formatReport(sessions);
    assert.ok(report.includes('Orchestra Token Report'));
  });

  it('contains "TOTAL" row with data', () => {
    const sessions = [
      {
        filename: 'session.jsonl',
        totalInput: 1000,
        totalOutput: 500,
        totalCacheCreation: 200,
        totalCacheRead: 100,
        cost: { totalCost: 0.05 },
        firstTimestamp: '2026-03-01T10:00:00Z',
        lastTimestamp: '2026-03-01T11:00:00Z',
      },
    ];
    const report = formatReport(sessions);
    assert.ok(report.includes('TOTAL'));
  });

  it('shows session count', () => {
    const sessions = [
      {
        filename: 'a.jsonl',
        totalInput: 100,
        totalOutput: 50,
        totalCacheCreation: 0,
        totalCacheRead: 0,
        cost: { totalCost: 1.0 },
        firstTimestamp: '2026-03-01T10:00:00Z',
        lastTimestamp: '2026-03-01T11:00:00Z',
      },
      {
        filename: 'b.jsonl',
        totalInput: 200,
        totalOutput: 100,
        totalCacheCreation: 0,
        totalCacheRead: 0,
        cost: { totalCost: 2.0 },
        firstTimestamp: '2026-03-01T12:00:00Z',
        lastTimestamp: '2026-03-01T13:00:00Z',
      },
    ];
    const report = formatReport(sessions);
    assert.ok(report.includes('Sessions: 2'));
  });

  it('sums totals across multiple sessions', () => {
    const sessions = [
      {
        filename: 'a.jsonl',
        totalInput: 1000,
        totalOutput: 500,
        totalCacheCreation: 0,
        totalCacheRead: 0,
        cost: { totalCost: 1.5 },
      },
      {
        filename: 'b.jsonl',
        totalInput: 2000,
        totalOutput: 1000,
        totalCacheCreation: 0,
        totalCacheRead: 0,
        cost: { totalCost: 3.0 },
      },
    ];
    const report = formatReport(sessions);
    // Total input: 3000, total output: 1500, total cost: $4.50
    assert.ok(report.includes('3,000'));
    assert.ok(report.includes('1,500'));
    assert.ok(report.includes('$4.50'));
  });

  it('includes session filenames in breakdown', () => {
    const sessions = [
      {
        filename: 'my-session.jsonl',
        totalInput: 100,
        totalOutput: 50,
        totalCacheCreation: 0,
        totalCacheRead: 0,
        cost: { totalCost: 0.01 },
      },
    ];
    const report = formatReport(sessions, { breakdown: true });
    assert.ok(report.includes('my-session.jsonl'));
  });

  it('handles missing cost gracefully', () => {
    const sessions = [
      {
        filename: 'nocost.jsonl',
        totalInput: 100,
        totalOutput: 50,
        totalCacheCreation: 0,
        totalCacheRead: 0,
      },
    ];
    const report = formatReport(sessions);
    assert.ok(report.includes('TOTAL'));
    assert.ok(report.includes('$0.00'));
  });

  it('breakdown:false does NOT show session filenames', () => {
    const sessions = [
      {
        filename: 'hidden-session.jsonl',
        totalInput: 100,
        totalOutput: 50,
        totalCacheCreation: 0,
        totalCacheRead: 0,
        cost: { totalCost: 0.01 },
      },
    ];
    const report = formatReport(sessions, { breakdown: false });
    assert.ok(!report.includes('hidden-session.jsonl'));
    assert.ok(report.includes('TOTAL'));
  });

  it('default options (no breakdown) does NOT show session filenames', () => {
    const sessions = [
      {
        filename: 'should-not-appear.jsonl',
        totalInput: 100,
        totalOutput: 50,
        totalCacheCreation: 0,
        totalCacheRead: 0,
        cost: { totalCost: 0.01 },
      },
    ];
    const report = formatReport(sessions);
    assert.ok(!report.includes('should-not-appear.jsonl'));
  });

  it('sums totalCost correctly across sessions', () => {
    const sessions = [
      {
        filename: 'a.jsonl',
        totalInput: 0, totalOutput: 0, totalCacheCreation: 0, totalCacheRead: 0,
        cost: { totalCost: 1.25 },
      },
      {
        filename: 'b.jsonl',
        totalInput: 0, totalOutput: 0, totalCacheCreation: 0, totalCacheRead: 0,
        cost: { totalCost: 3.75 },
      },
    ];
    const report = formatReport(sessions, { breakdown: false });
    assert.ok(report.includes('$5.00'));
  });

  it('handles sessions with different models (cost pre-calculated)', () => {
    const sessions = [
      {
        filename: 'opus.jsonl',
        totalInput: 1000, totalOutput: 500, totalCacheCreation: 0, totalCacheRead: 0,
        cost: { totalCost: 10.0 },
      },
      {
        filename: 'sonnet.jsonl',
        totalInput: 1000, totalOutput: 500, totalCacheCreation: 0, totalCacheRead: 0,
        cost: { totalCost: 2.0 },
      },
    ];
    const report = formatReport(sessions, { breakdown: true });
    assert.ok(report.includes('opus.jsonl'));
    assert.ok(report.includes('sonnet.jsonl'));
    assert.ok(report.includes('$12.00'));
  });
});

describe('formatTimestamp', () => {
  it('formats ISO timestamp to readable date', () => {
    const result = formatTimestamp('2026-03-01T10:30:00Z');
    assert.ok(result.includes('2026'));
    assert.ok(result.includes('03'));
    assert.ok(result.includes('01'));
  });

  it('returns empty string for null', () => {
    assert.equal(formatTimestamp(null), '');
  });

  it('returns empty string for undefined', () => {
    assert.equal(formatTimestamp(undefined), '');
  });

  it('returns empty string for empty string', () => {
    assert.equal(formatTimestamp(''), '');
  });
});
