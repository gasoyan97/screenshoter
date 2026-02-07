const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  capture: (mode) => ipcRenderer.invoke('capture', mode),
  quit: () => ipcRenderer.invoke('quit'),
  saveScreenshot: (data) => ipcRenderer.invoke('save-screenshot', data),
  getYandexToken: () => ipcRenderer.invoke('get-yandex-token'),
  setYandexToken: (token) => ipcRenderer.invoke('set-yandex-token', token),
  openExternal: (url) => ipcRenderer.invoke('open-external', url),
  onSetImage: (cb) => ipcRenderer.on('set-image', (_, dataUrl) => cb(dataUrl)),
});
