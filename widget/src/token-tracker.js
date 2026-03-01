const fs = require('fs');
const path = require('path');
const os = require('os');

// Цены за 1M токенов (USD)
const PRICING = {
  'claude-opus-4-6':   { input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.50 },
  'claude-sonnet-4-6': { input: 3,  output: 15, cacheWrite: 3.75,  cacheRead: 0.30 },
  'claude-haiku-4-5-20251001': { input: 0.80, output: 4, cacheWrite: 1.00, cacheRead: 0.08 }
};

const DEFAULT_PRICING = { input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.50 };

function getPricing(model) {
  if (!model) return DEFAULT_PRICING;
  for (const [key, val] of Object.entries(PRICING)) {
    if (model.includes(key) || key.includes(model)) return val;
  }
  if (model.includes('opus')) return PRICING['claude-opus-4-6'];
  if (model.includes('sonnet')) return PRICING['claude-sonnet-4-6'];
  if (model.includes('haiku')) return PRICING['claude-haiku-4-5-20251001'];
  return DEFAULT_PRICING;
}

function tokenCost(tokens, pricePerMillion) {
  return (tokens / 1_000_000) * pricePerMillion;
}

/**
 * projectId из пути: /Users/x/orchestra -> -Users-x-orchestra
 */
function projectIdFromPath(projectPath) {
  return projectPath.split('/').join('-');
}

/**
 * Парсит JSONL файл и считает токены (только записи после sinceTs).
 */
function parseSessionFile(filePath, sinceTs) {
  const result = { input: 0, output: 0, cacheWrite: 0, cacheRead: 0, cost: 0, calls: 0 };

  let content;
  try {
    content = fs.readFileSync(filePath, 'utf-8');
  } catch {
    return result;
  }

  const lines = content.split('\n');
  for (const line of lines) {
    if (!line.includes('"role":"assistant"')) continue;

    let record;
    try {
      record = JSON.parse(line);
    } catch {
      continue;
    }

    if (sinceTs && record.timestamp) {
      const ts = new Date(record.timestamp).getTime();
      if (ts < sinceTs) continue;
    }

    const usage = record.message?.usage;
    if (!usage) continue;

    const model = record.message?.model;
    const prices = getPricing(model);

    const inp = usage.input_tokens || 0;
    const out = usage.output_tokens || 0;
    const cw = usage.cache_creation_input_tokens || 0;
    const cr = usage.cache_read_input_tokens || 0;

    result.input += inp;
    result.output += out;
    result.cacheWrite += cw;
    result.cacheRead += cr;
    result.calls++;

    result.cost += tokenCost(inp, prices.input)
                 + tokenCost(out, prices.output)
                 + tokenCost(cw, prices.cacheWrite)
                 + tokenCost(cr, prices.cacheRead);
  }

  return result;
}

/**
 * Считает токены оркестратора.
 *
 * @param {string} orchestraPath — путь к проекту
 * @param {string|null} startedAt — ISO timestamp начала прогона оркестратора.
 *   Только сессии, созданные после этого момента, будут учтены.
 *   Если null — возвращает null (оркестратор не работал).
 */
function fetchOrchestraTokens(orchestraPath, startedAt) {
  if (!startedAt) return null;

  const sinceTs = new Date(startedAt).getTime();
  if (isNaN(sinceTs)) return null;

  const projectId = projectIdFromPath(orchestraPath);
  const projectDir = path.join(os.homedir(), '.claude', 'projects', projectId);

  if (!fs.existsSync(projectDir)) return null;

  let files;
  try {
    files = fs.readdirSync(projectDir).filter(f => f.endsWith('.jsonl'));
  } catch {
    return null;
  }

  const totals = { input: 0, output: 0, cacheWrite: 0, cacheRead: 0, cost: 0, calls: 0 };

  for (const file of files) {
    const filePath = path.join(projectDir, file);

    // Фильтрация по записям внутри файла (sinceTs в parseSessionFile)
    // Файловый фильтр по birthtimeMs убран — ненадёжен при неточном started_at

    const session = parseSessionFile(filePath, sinceTs);
    totals.input += session.input;
    totals.output += session.output;
    totals.cacheWrite += session.cacheWrite;
    totals.cacheRead += session.cacheRead;
    totals.cost += session.cost;
    totals.calls += session.calls;
  }

  return {
    inputTokens: totals.input,
    outputTokens: totals.output,
    cacheWriteTokens: totals.cacheWrite,
    cacheReadTokens: totals.cacheRead,
    totalTokens: totals.input + totals.output + totals.cacheWrite + totals.cacheRead,
    totalCost: Math.round(totals.cost * 100) / 100,
    apiCalls: totals.calls
  };
}

module.exports = { fetchOrchestraTokens };
