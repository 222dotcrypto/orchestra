const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

const { PRICING, calculateCost } = require('../src/pricing');

describe('PRICING constants', () => {
  it('contains opus, sonnet and haiku models', () => {
    assert.ok(PRICING['claude-opus-4-6']);
    assert.ok(PRICING['claude-sonnet-4-6']);
    assert.ok(PRICING['claude-haiku-4-5-20251001']);
  });

  it('opus input price is 15 per 1M tokens', () => {
    assert.equal(PRICING['claude-opus-4-6'].input, 15);
  });

  it('sonnet output price is 15 per 1M tokens', () => {
    assert.equal(PRICING['claude-sonnet-4-6'].output, 15);
  });
});

describe('calculateCost', () => {
  it('calculates opus input cost: 1M tokens → $15', () => {
    const result = calculateCost('claude-opus-4-6', {
      input: 1_000_000,
      output: 0,
      cacheCreation: 0,
      cacheRead: 0,
    });
    assert.equal(result.inputCost, 15);
    assert.equal(result.outputCost, 0);
    assert.equal(result.totalCost, 15);
  });

  it('calculates opus output cost: 1M tokens → $75', () => {
    const result = calculateCost('claude-opus-4-6', {
      input: 0,
      output: 1_000_000,
      cacheCreation: 0,
      cacheRead: 0,
    });
    assert.equal(result.outputCost, 75);
    assert.equal(result.totalCost, 75);
  });

  it('calculates sonnet output cost: 1M tokens → $15', () => {
    const result = calculateCost('claude-sonnet-4-6', {
      input: 0,
      output: 1_000_000,
      cacheCreation: 0,
      cacheRead: 0,
    });
    assert.equal(result.outputCost, 15);
    assert.equal(result.totalCost, 15);
  });

  it('calculates sonnet input cost: 1M tokens → $3', () => {
    const result = calculateCost('claude-sonnet-4-6', {
      input: 1_000_000,
      output: 0,
      cacheCreation: 0,
      cacheRead: 0,
    });
    assert.equal(result.inputCost, 3);
  });

  it('calculates cache costs correctly for opus', () => {
    const result = calculateCost('claude-opus-4-6', {
      input: 0,
      output: 0,
      cacheCreation: 1_000_000,
      cacheRead: 1_000_000,
    });
    assert.equal(result.cacheCreationCost, 18.75);
    assert.equal(result.cacheReadCost, 1.5);
    assert.equal(result.totalCost, 20.25);
  });

  it('calculates total cost with all components', () => {
    const result = calculateCost('claude-opus-4-6', {
      input: 1_000_000,
      output: 1_000_000,
      cacheCreation: 1_000_000,
      cacheRead: 1_000_000,
    });
    // 15 + 75 + 18.75 + 1.5 = 110.25
    assert.equal(result.totalCost, 110.25);
  });

  it('fallback: "claude-opus-4-20250514" resolves to opus pricing', () => {
    const result = calculateCost('claude-opus-4-20250514', {
      input: 1_000_000,
      output: 0,
      cacheCreation: 0,
      cacheRead: 0,
    });
    assert.equal(result.inputCost, 15);
  });

  it('fallback: unknown model resolves to sonnet pricing', () => {
    const result = calculateCost('some-unknown-model', {
      input: 1_000_000,
      output: 0,
      cacheCreation: 0,
      cacheRead: 0,
    });
    // sonnet input = $3 per 1M
    assert.equal(result.inputCost, 3);
  });

  it('fallback: model with "haiku" substring resolves to haiku pricing', () => {
    const result = calculateCost('claude-haiku-next-gen', {
      input: 1_000_000,
      output: 0,
      cacheCreation: 0,
      cacheRead: 0,
    });
    assert.equal(result.inputCost, 0.8);
  });

  it('handles zero usage', () => {
    const result = calculateCost('claude-opus-4-6', {
      input: 0,
      output: 0,
      cacheCreation: 0,
      cacheRead: 0,
    });
    assert.equal(result.totalCost, 0);
  });

  it('handles missing usage fields', () => {
    const result = calculateCost('claude-opus-4-6', {});
    assert.equal(result.inputCost, 0);
    assert.equal(result.outputCost, 0);
    assert.equal(result.cacheCreationCost, 0);
    assert.equal(result.cacheReadCost, 0);
    assert.equal(result.totalCost, 0);
  });

  it('handles fractional token counts', () => {
    const result = calculateCost('claude-sonnet-4-6', {
      input: 500_000,
      output: 0,
      cacheCreation: 0,
      cacheRead: 0,
    });
    assert.equal(result.inputCost, 1.5);
  });
});
