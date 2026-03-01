const { app, BrowserWindow, ipcMain, Menu, screen } = require('electron');
const path = require('path');
const fs = require('fs');
const Store = require('electron-store');
const AutoLaunch = require('auto-launch');
const { fetchOrchestraData } = require('./src/orchestra-fetcher');

let autoLauncher;

const store = new Store({
  defaults: {
    windowX: null,
    windowY: null,
    compact: false,
    autoLaunch: false,
    orchestraPath: null
  }
});

let mainWindow;
let fetchInterval;
let isCompact = store.get('compact');

const WINDOW_WIDTH = 320;
const WINDOW_HEIGHT_DEFAULT = 200;
const WINDOW_HEIGHT_COMPACT = 44;
const FETCH_INTERVAL_MS = 5000;

let currentFullHeight = WINDOW_HEIGHT_DEFAULT;

function getOrchestraPath() {
  // Приоритет: active-path файл от runner.sh → electron-store → ~/orchestra
  const activePathFile = path.join(app.getPath('home'), '.orchestra-active-path');
  try {
    const activePath = fs.readFileSync(activePathFile, 'utf-8').trim();
    if (activePath && fs.existsSync(path.join(activePath, '.brain'))) {
      return activePath;
    }
  } catch {}

  let p = store.get('orchestraPath');
  if (p) return p;
  p = path.join(app.getPath('home'), 'orchestra');
  store.set('orchestraPath', p);
  return p;
}

function createWindow() {
  const { width: screenWidth, height: screenHeight } = screen.getPrimaryDisplay().workAreaSize;

  const savedX = store.get('windowX');
  const savedY = store.get('windowY');
  const x = savedX !== null ? savedX : screenWidth - WINDOW_WIDTH - 20;
  const y = savedY !== null ? savedY : screenHeight - WINDOW_HEIGHT_DEFAULT - 20;

  mainWindow = new BrowserWindow({
    width: WINDOW_WIDTH,
    height: isCompact ? WINDOW_HEIGHT_COMPACT : WINDOW_HEIGHT_DEFAULT,
    x,
    y,
    alwaysOnTop: true,
    frame: false,
    transparent: true,
    skipTaskbar: true,
    resizable: false,
    hasShadow: true,
    vibrancy: 'dark',
    visualEffectState: 'active',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));

  mainWindow.on('moved', () => {
    const [wx, wy] = mainWindow.getPosition();
    store.set('windowX', wx);
    store.set('windowY', wy);
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
  });

  fetchAndSend();
  fetchInterval = setInterval(fetchAndSend, FETCH_INTERVAL_MS);
}

async function fetchAndSend() {
  if (!mainWindow) return;
  mainWindow.webContents.send('fetch-start');
  try {
    const orchestraPath = getOrchestraPath();
    const data = await fetchOrchestraData(orchestraPath);
    mainWindow.webContents.send('orchestra-data', data);
  } catch (err) {
    mainWindow.webContents.send('orchestra-error', err.message);
  }
}

// IPC handlers
ipcMain.on('show-context-menu', (event) => {
  const template = [
    { label: 'Обновить', click: () => fetchAndSend() },
    { label: isCompact ? 'Развернуть' : 'Компактный режим', click: () => toggleCompact() },
    { type: 'separator' },
    { label: 'Сбросить позицию', click: () => resetPosition() },
    {
      label: store.get('autoLaunch') ? 'Автозапуск ✓' : 'Автозапуск',
      click: () => toggleAutoLaunch()
    },
    { type: 'separator' },
    { label: 'Выход', click: () => app.quit() }
  ];
  const menu = Menu.buildFromTemplate(template);
  menu.popup(BrowserWindow.fromWebContents(event.sender));
});

ipcMain.on('toggle-compact', () => toggleCompact());

ipcMain.on('resize-window', (_e, height) => {
  if (!mainWindow || isCompact) return;
  const h = Math.max(100, Math.min(500, Math.ceil(height)));
  if (h !== currentFullHeight) {
    currentFullHeight = h;
    mainWindow.setSize(WINDOW_WIDTH, h);
  }
});

function toggleCompact() {
  isCompact = !isCompact;
  store.set('compact', isCompact);
  if (mainWindow) {
    mainWindow.setSize(WINDOW_WIDTH, isCompact ? WINDOW_HEIGHT_COMPACT : currentFullHeight);
    mainWindow.webContents.send('compact-changed', isCompact);
  }
}

function resetPosition() {
  const { width: screenWidth, height: screenHeight } = screen.getPrimaryDisplay().workAreaSize;
  const x = screenWidth - WINDOW_WIDTH - 20;
  const y = screenHeight - currentFullHeight - 20;
  if (mainWindow) {
    mainWindow.setPosition(x, y);
    store.set('windowX', x);
    store.set('windowY', y);
  }
}

function toggleAutoLaunch() {
  const enabled = !store.get('autoLaunch');
  store.set('autoLaunch', enabled);
  if (enabled) autoLauncher.enable().catch(() => {});
  else autoLauncher.disable().catch(() => {});
}

app.dock?.hide();

app.whenReady().then(() => {
  autoLauncher = new AutoLaunch({
    name: 'Orchestra Widget',
    path: app.getPath('exe')
  });
  createWindow();
});

app.on('window-all-closed', () => {
  if (fetchInterval) clearInterval(fetchInterval);
  app.quit();
});
