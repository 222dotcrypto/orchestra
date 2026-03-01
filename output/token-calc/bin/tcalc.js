#!/usr/bin/env node
'use strict';

const path = require('path');
const os = require('os');
const fs = require('fs');
const { findSessions, parseSession } = require('../src/parser');
const { calculateCost } = require('../src/pricing');
const { formatReport } = require('../src/formatter');

const VERSION = require('../package.json').version;

const HELP = `tcalc v${VERSION} — Token cost calculator for Claude Code sessions

Использование: tcalc [опции]

Опции:
  --breakdown        Показать разбивку по сессиям
  --since <date>     Показать сессии начатые после указанной даты (ISO 8601)
  --session <path>   Анализировать конкретный JSONL-файл
  --help, -h         Показать эту справку
  --version, -v      Показать версию
`;

function parseArgs(argv) {
  const args = argv.slice(2);
  const result = { breakdown: false, since: null, session: null, help: false, version: false };

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--breakdown') {
      result.breakdown = true;
    } else if (args[i] === '--since') {
      if (!args[i + 1]) {
        console.error('Ошибка: --since требует значение (ISO 8601 дата)');
        process.exit(1);
      }
      result.since = args[++i];
    } else if (args[i] === '--session') {
      if (!args[i + 1]) {
        console.error('Ошибка: --session требует путь к файлу');
        process.exit(1);
      }
      result.session = args[++i];
    } else if (args[i] === '--help' || args[i] === '-h') {
      result.help = true;
    } else if (args[i] === '--version' || args[i] === '-v') {
      result.version = true;
    } else {
      console.error(`Неизвестный аргумент: ${args[i]}\nИспользуй --help для справки.`);
      process.exit(1);
    }
  }

  return result;
}

function resolveProjectDir() {
  const cwd = process.cwd();
  const projectName = cwd.replace(/\//g, '-');
  const projectsRoot = path.join(os.homedir(), '.claude', 'projects');

  if (!fs.existsSync(projectsRoot)) return null;

  const dirs = fs.readdirSync(projectsRoot);
  const match = dirs.find(d => d === projectName);
  if (match) return path.join(projectsRoot, match);

  return null;
}

async function main() {
  const args = parseArgs(process.argv);

  if (args.help) { console.log(HELP); return; }
  if (args.version) { console.log(`tcalc v${VERSION}`); return; }

  let sessionPaths;

  if (args.session) {
    const absPath = path.resolve(args.session);
    if (!fs.existsSync(absPath)) {
      console.error(`File not found: ${absPath}`);
      process.exit(1);
    }
    sessionPaths = [absPath];
  } else {
    const projectDir = resolveProjectDir();
    if (!projectDir) {
      console.error('Project directory not found in ~/.claude/projects/');
      process.exit(1);
    }
    sessionPaths = findSessions(projectDir);
  }

  if (sessionPaths.length === 0) {
    console.log(formatReport([], { breakdown: false }));
    return;
  }

  const sessions = [];

  for (const sp of sessionPaths) {
    const parsed = await parseSession(sp);
    const cost = calculateCost(parsed.model || 'claude-sonnet-4-6', {
      input: parsed.totalInput,
      output: parsed.totalOutput,
      cacheCreation: parsed.totalCacheCreation,
      cacheRead: parsed.totalCacheRead,
    });
    parsed.cost = cost;
    sessions.push(parsed);
  }

  let filtered = sessions;

  if (args.since) {
    const sinceDate = new Date(args.since);
    filtered = sessions.filter(s => {
      if (!s.firstTimestamp) return false;
      return new Date(s.firstTimestamp) >= sinceDate;
    });
  }

  const report = formatReport(filtered, { breakdown: args.breakdown });
  console.log(report);
}

// Экспорт для тестирования
module.exports = { parseArgs, resolveProjectDir };

// Запуск CLI только при прямом вызове
if (require.main === module) {
  main().catch(err => {
    console.error(err.message);
    process.exit(1);
  });
}
