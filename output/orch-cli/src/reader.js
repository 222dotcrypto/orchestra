'use strict';

const fs = require('node:fs');
const path = require('node:path');

function findBrainRoot(startDir) {
  let dir = startDir || process.cwd();
  while (dir !== path.dirname(dir)) {
    if (fs.existsSync(path.join(dir, '.brain'))) {
      return path.join(dir, '.brain');
    }
    dir = path.dirname(dir);
  }
  return null;
}

function readJSON(filePath) {
  try {
    const content = fs.readFileSync(filePath, 'utf-8');
    return JSON.parse(content);
  } catch {
    return null;
  }
}

function readState(brainDir) {
  return readJSON(path.join(brainDir, 'state.json'));
}

function readWorkers(brainDir) {
  const dir = path.join(brainDir, 'workers');
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir)
    .filter(f => f.endsWith('.json'))
    .map(f => readJSON(path.join(dir, f)))
    .filter(Boolean)
    .sort((a, b) => (a.id || '').localeCompare(b.id || ''));
}

function readTasks(brainDir) {
  const dir = path.join(brainDir, 'tasks');
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir)
    .filter(f => f.endsWith('.json'))
    .map(f => readJSON(path.join(dir, f)))
    .filter(Boolean)
    .sort((a, b) => (a.id || '').localeCompare(b.id || ''));
}

function readAll(brainDir) {
  return {
    state: readState(brainDir),
    workers: readWorkers(brainDir),
    tasks: readTasks(brainDir),
  };
}

function readLog(brainDir, lines = 20) {
  const logPath = path.join(brainDir, 'logs', 'brain.log');
  try {
    const content = fs.readFileSync(logPath, 'utf-8');
    const allLines = content.split('\n');
    return allLines.slice(-(lines + 1)).join('\n');
  } catch {
    return '';
  }
}

function getLogPath(brainDir) {
  return path.join(brainDir, 'logs', 'brain.log');
}

module.exports = { findBrainRoot, readJSON, readState, readWorkers, readTasks, readAll, readLog, getLogPath };
