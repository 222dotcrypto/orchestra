const fs = require('fs');
const path = require('path');
const { fetchOrchestraTokens } = require('./token-tracker');

function readJsonDir(dirPath, pattern) {
  try {
    const files = fs.readdirSync(dirPath).filter(f => f.match(pattern) && f.endsWith('.json'));
    return files.map(f => {
      try {
        return JSON.parse(fs.readFileSync(path.join(dirPath, f), 'utf-8'));
      } catch {
        return null;
      }
    }).filter(Boolean);
  } catch {
    return [];
  }
}

function readJson(filePath, fallback) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf-8'));
  } catch {
    return fallback;
  }
}

function countFiles(dirPath, ext) {
  try {
    return fs.readdirSync(dirPath).filter(f => f.endsWith(ext)).length;
  } catch {
    return 0;
  }
}

async function fetchOrchestraData(orchestraPath) {
  const brainDir = path.join(orchestraPath, '.brain');

  const state = readJson(path.join(brainDir, 'state.json'), {
    status: 'idle',
    current_task: null,
    current_phase: 0,
    phases: [],
    workers_active: 0,
    tasks_total: 0,
    tasks_done: 0,
    tasks_failed: 0,
    started_at: null
  });

  const workers = readJsonDir(path.join(brainDir, 'workers'), /^worker-/);
  const allTasks = readJsonDir(path.join(brainDir, 'tasks'), /^task-/);

  // Фильтруем задачи только текущего прогона (по ID из state.phases)
  const currentTaskIds = new Set(
    (state.phases || []).flatMap(p => p.tasks || [])
  );
  const tasks = currentTaskIds.size > 0
    ? allTasks.filter(t => currentTaskIds.has(t.id))
    : allTasks;

  // Токены: только сессии воркеров, созданные после started_at
  const tokens = fetchOrchestraTokens(orchestraPath, state.started_at);

  const activeWorkers = workers.filter(w => w.status === 'busy' || w.status === 'idle');

  // Signals
  const signalsDir = path.join(brainDir, 'signals');
  const signalsDone = countFiles(signalsDir, '.done');
  const signalsFailed = countFiles(signalsDir, '.failed');
  const signalsSuspicious = countFiles(signalsDir, '.suspicious');

  // Checkpoints
  const checkpointsDir = path.join(brainDir, 'checkpoints');
  const checkpoints = readJsonDir(checkpointsDir, /checkpoint/);

  // Reworks
  const reworkCount = tasks.reduce((sum, t) => sum + (t.rework_count || 0), 0);

  // Phase info
  const phases = state.phases || [];
  const totalPhases = phases.length;
  const currentPhase = state.current_phase || 0;
  const phasesDone = phases.filter(p => p.status === 'done').length;

  return {
    state,
    workers,
    tasks,
    tokens,
    computed: {
      activeCount: activeWorkers.length,
      tasksDone: tasks.filter(t => t.status === 'done').length,
      tasksTotal: tasks.length,
      tasksInProgress: tasks.filter(t => t.status === 'in_progress').length,
      tasksFailed: tasks.filter(t => t.status === 'failed').length,
      reworkCount,
      signalsDone,
      signalsFailed,
      signalsSuspicious,
      currentPhase,
      totalPhases,
      phasesDone,
      checkpoints: checkpoints.length
    }
  };
}

module.exports = { fetchOrchestraData };
