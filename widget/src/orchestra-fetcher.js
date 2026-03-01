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

async function fetchOrchestraData(orchestraPath) {
  const brainDir = path.join(orchestraPath, '.brain');

  const state = readJson(path.join(brainDir, 'state.json'), {
    status: 'idle',
    current_task: null,
    phase: 0,
    total_phases: 0,
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
  const stuckWorkers = workers.filter(w => {
    if (w.status !== 'busy' || !w.last_heartbeat) return false;
    const diff = Date.now() - new Date(w.last_heartbeat).getTime();
    return diff > 120000;
  });

  return {
    state,
    workers,
    tasks,
    tokens,
    computed: {
      activeCount: activeWorkers.length,
      stuckCount: stuckWorkers.length,
      tasksDone: tasks.filter(t => t.status === 'done').length,
      tasksTotal: tasks.length,
      tasksInProgress: tasks.filter(t => t.status === 'in_progress').length,
      tasksReview: tasks.filter(t => t.status === 'review').length,
      tasksFailed: tasks.filter(t => t.status === 'failed').length
    }
  };
}

module.exports = { fetchOrchestraData };
