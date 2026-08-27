const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('quota', { getSnapshot: () => ipcRenderer.invoke('snapshot'), refresh: () => ipcRenderer.send('refresh'), settings: value => ipcRenderer.send('settings', value), onSnapshot: callback => ipcRenderer.on('snapshot', (_, value) => callback(value)) });
