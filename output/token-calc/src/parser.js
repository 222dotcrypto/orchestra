const fs = require('fs');
const path = require('path');
const readline = require('readline');

function findSessions(projectDir) {
  const absDir = path.resolve(projectDir);
  if (!fs.existsSync(absDir)) return [];

  return fs.readdirSync(absDir)
    .filter(f => f.endsWith('.jsonl'))
    .map(f => path.join(absDir, f))
    .sort((a, b) => fs.statSync(a).mtimeMs - fs.statSync(b).mtimeMs);
}

async function parseSession(filePath) {
  const result = {
    filename: path.basename(filePath),
    model: null,
    totalInput: 0,
    totalOutput: 0,
    totalCacheCreation: 0,
    totalCacheRead: 0,
    firstTimestamp: null,
    lastTimestamp: null,
  };

  try {
    fs.accessSync(filePath, fs.constants.R_OK);
  } catch {
    throw new Error(`Не удалось прочитать файл: ${filePath}`);
  }

  const rl = readline.createInterface({
    input: fs.createReadStream(filePath),
    crlfDelay: Infinity,
  });

  for await (const line of rl) {
    if (!line.trim()) continue;

    let entry;
    try {
      entry = JSON.parse(line);
    } catch {
      continue;
    }

    if (entry.type !== 'assistant') continue;

    const usage = entry.message?.usage;
    if (!usage) continue;

    if (!result.model && entry.message?.model) {
      result.model = entry.message.model;
    }

    result.totalInput += usage.input_tokens || 0;
    result.totalOutput += usage.output_tokens || 0;
    result.totalCacheCreation += usage.cache_creation_input_tokens || 0;
    result.totalCacheRead += usage.cache_read_input_tokens || 0;

    const ts = entry.timestamp || null;
    if (ts) {
      if (!result.firstTimestamp || ts < result.firstTimestamp) {
        result.firstTimestamp = ts;
      }
      if (!result.lastTimestamp || ts > result.lastTimestamp) {
        result.lastTimestamp = ts;
      }
    }
  }

  return result;
}

module.exports = { findSessions, parseSession };
