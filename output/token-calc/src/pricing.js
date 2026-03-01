'use strict';

const PRICING = {
  'claude-opus-4-6': {
    input: 15,
    output: 75,
    cacheCreation: 18.75,
    cacheRead: 1.50
  },
  'claude-sonnet-4-6': {
    input: 3,
    output: 15,
    cacheCreation: 3.75,
    cacheRead: 0.30
  },
  'claude-haiku-4-5-20251001': {
    input: 0.80,
    output: 4,
    cacheCreation: 1,
    cacheRead: 0.08
  }
};

const FALLBACK_SUBSTRINGS = ['opus', 'sonnet', 'haiku'];
const DEFAULT_MODEL = 'claude-sonnet-4-6';

function resolvePricing(model) {
  if (PRICING[model]) return PRICING[model];

  const lower = model.toLowerCase();
  for (const sub of FALLBACK_SUBSTRINGS) {
    if (lower.includes(sub)) {
      const match = Object.keys(PRICING).find(k => k.includes(sub));
      if (match) return PRICING[match];
    }
  }

  return PRICING[DEFAULT_MODEL];
}

function calculateCost(model, usage) {
  const prices = resolvePricing(model);
  const perToken = 1_000_000;

  const inputCost = ((usage.input || 0) / perToken) * prices.input;
  const outputCost = ((usage.output || 0) / perToken) * prices.output;
  const cacheCreationCost = ((usage.cacheCreation || 0) / perToken) * prices.cacheCreation;
  const cacheReadCost = ((usage.cacheRead || 0) / perToken) * prices.cacheRead;
  const totalCost = inputCost + outputCost + cacheCreationCost + cacheReadCost;

  return { inputCost, outputCost, cacheCreationCost, cacheReadCost, totalCost };
}

module.exports = { PRICING, calculateCost };
