// DOM refs
const $ = (id) => document.getElementById(id);

const el = {
  mainView: $('main-view'),
  compactView: $('compact-view'),
  errorView: $('error-view'),
  statusBadge: $('status-badge'),
  indicator: $('indicator'),
  mWorkers: $('m-workers'),
  mPhase: $('m-phase'),
  mTasks: $('m-tasks'),
  infoRow: $('info-row'),
  infoSignals: $('info-signals'),
  infoReworks: $('info-reworks'),
  infoSuspicious: $('info-suspicious'),
  progressSection: $('progress-section'),
  tasksBar: $('tasks-bar'),
  tasksPct: $('tasks-pct'),
  workersSection: $('workers-section'),
  workersList: $('workers-list'),
  tIn: $('t-in'),
  tOut: $('t-out'),
  tCost: $('t-cost'),
  statusCompact: $('status-compact'),
  phaseCompact: $('phase-compact'),
  workersCompact: $('workers-compact'),
  tasksCompact: $('tasks-compact'),
  indicatorCompact: $('indicator-compact')
};

// Форматирование чисел
function fmtTokens(n) {
  if (n == null) return '—';
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M';
  if (n >= 1_000) return (n / 1_000).toFixed(1) + 'k';
  return String(n);
}

function fmtCost(n) {
  if (n == null) return '—';
  return n.toFixed(2);
}

// Статус → CSS класс
const statusClass = {
  idle: 'status-idle',
  planning: 'status-planning',
  executing: 'status-executing',
  reviewing: 'status-reviewing',
  done: 'status-done',
  failed: 'status-failed'
};

function setStatus(badge, status) {
  badge.className = 'status-badge ' + (statusClass[status] || 'status-idle');
  badge.textContent = status || 'idle';
}

// Рендер списка воркеров
function renderWorkers(workers) {
  const active = (workers || []).filter(w => w.status === 'busy' || w.status === 'idle' || w.status === 'stuck');

  if (active.length === 0) {
    el.workersSection.classList.add('hidden');
    return;
  }

  el.workersSection.classList.remove('hidden');
  el.workersList.innerHTML = active.map(w => {
    const st = w.status || 'idle';
    const isBusy = st === 'busy';
    return `<div class="worker-row ${isBusy ? 'worker-busy' : ''}">
      <span class="worker-dot ${st}"></span>
      <span class="worker-id">${w.id || '?'}</span>
      <span class="worker-role">${w.role || '—'}</span>
      <span class="worker-status-lbl ${st}">${st}</span>
    </div>`;
  }).join('');
}

// Основные данные оркестратора
window.api.onOrchestraData((data) => {
  el.errorView.classList.add('hidden');

  const { state, workers, computed, tokens } = data;
  const status = state.status || 'idle';
  const isOff = status === 'idle' || status === 'done';
  const isActive = !isOff;

  // Когда оркестратор выключен — сброс в чистое состояние
  if (isOff) {
    setStatus(el.statusBadge, 'idle');
    setStatus(el.statusCompact, 'idle');
    el.indicator.classList.remove('pulse');
    el.indicatorCompact.classList.remove('pulse');
    el.mWorkers.textContent = '0';
    el.mPhase.textContent = '—';
    el.mTasks.textContent = '0/0';
    el.phaseCompact.textContent = '—';
    el.workersCompact.textContent = '0';
    el.tasksCompact.textContent = '0/0';
    el.progressSection.classList.add('hidden');
    el.workersSection.classList.add('hidden');
    el.infoRow.classList.add('hidden');
    // Токены последнего прогона — показываем если есть
    if (tokens) {
      el.tIn.textContent = fmtTokens(tokens.inputTokens + tokens.cacheReadTokens);
      el.tOut.textContent = fmtTokens(tokens.outputTokens);
      el.tCost.textContent = fmtCost(tokens.totalCost);
    } else {
      el.tIn.textContent = '—';
      el.tOut.textContent = '—';
      el.tCost.textContent = '—';
    }
    requestAnimationFrame(autoResize);
    return;
  }

  // Статус
  setStatus(el.statusBadge, status);
  setStatus(el.statusCompact, status);

  // Индикатор пульса
  el.indicator.classList.toggle('pulse', isActive);
  el.indicatorCompact.classList.toggle('pulse', isActive);

  // Метрики
  el.mWorkers.textContent = computed.activeCount;
  el.mPhase.textContent = computed.totalPhases > 0
    ? computed.currentPhase + '/' + computed.totalPhases
    : '—';
  el.mTasks.textContent = computed.tasksDone + '/' + computed.tasksTotal;

  // Compact
  el.phaseCompact.textContent = computed.totalPhases > 0
    ? computed.currentPhase + '/' + computed.totalPhases
    : '—';
  el.workersCompact.textContent = computed.activeCount;
  el.tasksCompact.textContent = computed.tasksDone + '/' + computed.tasksTotal;

  // Info row (signals, reworks, suspicious)
  const hasInfo = computed.signalsDone > 0 || computed.signalsFailed > 0
    || computed.signalsSuspicious > 0 || computed.reworkCount > 0;
  el.infoRow.classList.toggle('hidden', !hasInfo);
  el.infoSignals.textContent = (computed.signalsDone || 0) + '✓ ' + (computed.signalsFailed || 0) + '✗';
  el.infoReworks.textContent = computed.reworkCount > 0 ? computed.reworkCount + ' rework' : '';
  el.infoSuspicious.textContent = computed.signalsSuspicious > 0
    ? computed.signalsSuspicious + ' suspicious'
    : '';

  // Прогресс
  if (computed.tasksTotal > 0) {
    el.progressSection.classList.remove('hidden');
    const taskPct = Math.round((computed.tasksDone / computed.tasksTotal) * 100);
    el.tasksBar.style.width = taskPct + '%';
    el.tasksPct.textContent = computed.tasksDone + '/' + computed.tasksTotal;
  } else {
    el.progressSection.classList.add('hidden');
  }

  // Воркеры
  renderWorkers(workers);

  // Токены
  if (tokens) {
    el.tIn.textContent = fmtTokens(tokens.inputTokens + tokens.cacheReadTokens);
    el.tOut.textContent = fmtTokens(tokens.outputTokens);
    el.tCost.textContent = fmtCost(tokens.totalCost);
  }

  // Подстроить высоту окна под контент
  requestAnimationFrame(autoResize);
});

// Compact toggle
window.api.onCompactChanged((isCompact) => {
  el.mainView.classList.toggle('hidden', isCompact);
  el.compactView.classList.toggle('hidden', !isCompact);
});

// Ошибка
window.api.onOrchestraError((msg) => {
  el.errorView.classList.remove('hidden');
  el.errorView.querySelector('span').textContent = msg || 'Ошибка';
});

// Fetch индикатор — мигание при обновлении
window.api.onFetchStart(() => {
  el.indicator.style.opacity = '0.3';
  el.indicatorCompact.style.opacity = '0.3';
  setTimeout(() => {
    el.indicator.style.opacity = '1';
    el.indicatorCompact.style.opacity = '1';
  }, 300);
});

// Авторесайз окна под контент
function autoResize() {
  const view = el.mainView;
  if (view.classList.contains('hidden')) return;
  const h = view.scrollHeight + 2; // +2 для border
  window.api.resizeWindow(h);
}

// Контекстное меню по правому клику
document.addEventListener('contextmenu', (e) => {
  e.preventDefault();
  window.api.showContextMenu();
});

// Двойной клик — toggle compact
document.addEventListener('dblclick', () => {
  window.api.toggleCompact();
});
