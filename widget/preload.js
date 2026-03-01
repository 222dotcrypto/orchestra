const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
  onOrchestraData: (cb) => ipcRenderer.on('orchestra-data', (_e, data) => cb(data)),
  onOrchestraError: (cb) => ipcRenderer.on('orchestra-error', (_e, msg) => cb(msg)),
  onFetchStart: (cb) => ipcRenderer.on('fetch-start', () => cb()),
  onCompactChanged: (cb) => ipcRenderer.on('compact-changed', (_e, val) => cb(val)),
  showContextMenu: () => ipcRenderer.send('show-context-menu'),
  toggleCompact: () => ipcRenderer.send('toggle-compact'),
  resizeWindow: (h) => ipcRenderer.send('resize-window', h)
});
