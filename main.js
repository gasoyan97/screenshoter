const { app, BrowserWindow, ipcMain, Tray, Menu, dialog, shell, nativeImage } = require('electron');
const path = require('path');
const { spawn } = require('child_process');
const fs = require('fs').promises;
const os = require('os');

const Store = require('electron-store');
const store = new Store();

let tray = null;
let launcherWindow = null;
let annotationWindow = null;

const TEMP_DIR = path.join(os.tmpdir(), 'scrinsjater');
const getTempPath = (ext = 'png') => path.join(TEMP_DIR, `screenshot_${Date.now()}.${ext}`);

async function ensureTempDir() {
  try {
    await fs.mkdir(TEMP_DIR, { recursive: true });
  } catch (e) {
    console.error('Failed to create temp dir:', e);
  }
}

function captureScreen(mode) {
  return new Promise(async (resolve, reject) => {
    await ensureTempDir();
    const outputPath = getTempPath();

    const args = ['-x'];
    if (mode === 'window') {
      args.push('-w');
    } else if (mode === 'region') {
      args.push('-i');
    } else {
      args.push('-m');
    }
    args.push(outputPath);

    const proc = spawn('screencapture', args, { stdio: 'inherit' });
    proc.on('close', async (code) => {
      if (code !== 0) {
        try {
          await fs.unlink(outputPath);
        } catch (_) {}
        reject(new Error('Screenshot cancelled'));
        return;
      }
      try {
        const stat = await fs.stat(outputPath);
        if (stat.size > 0) {
          resolve(outputPath);
        } else {
          await fs.unlink(outputPath);
          reject(new Error('Screenshot cancelled'));
        }
      } catch (e) {
        reject(e);
      }
    });
  });
}

function createAnnotationWindow(imagePath) {
  if (annotationWindow) {
    annotationWindow.close();
  }

  annotationWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    minWidth: 400,
    minHeight: 300,
    title: 'Scrinsjater — Аннотации',
    backgroundColor: '#1a1a1e',
    titleBarStyle: 'hiddenInset',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
    show: false,
  });

  annotationWindow.loadFile('annotation.html');

  annotationWindow.once('ready-to-show', async () => {
    try {
      const img = nativeImage.createFromPath(imagePath);
      const dataUrl = img.toDataURL('image/png');
      annotationWindow.webContents.send('set-image', dataUrl);
    } catch (e) {
      console.error('Failed to load image:', e);
    }
    annotationWindow.show();
  });

  annotationWindow.on('closed', () => {
    annotationWindow = null;
    try {
      fs.unlink(imagePath).catch(() => {});
    } catch (_) {}
  });
}

function createTray() {
  try {
    const iconPath = path.join(__dirname, 'assets', 'iconTemplate.png');
    const icon = nativeImage.createFromPath(iconPath);
    if (!icon.isEmpty()) {
      tray = new Tray(icon.resize({ width: 22, height: 22 }));
      tray.setToolTip('Scrinsjater');
      tray.setContextMenu(Menu.buildFromTemplate([
        { label: 'Вся область экрана', click: () => triggerCapture('full') },
        { label: 'Окно (с тенью)', click: () => triggerCapture('window') },
        { label: 'Выбранная область', click: () => triggerCapture('region') },
        { type: 'separator' },
        { label: 'Настройки', click: () => openSettings() },
        { label: 'Выход', click: () => app.quit() },
      ]));
    }
  } catch (e) {
    console.error('Tray error:', e);
  }
}

function createLauncherWindow() {
  if (launcherWindow) {
    launcherWindow.focus();
    return;
  }
  launcherWindow = new BrowserWindow({
    width: 280,
    height: 280,
    title: 'Scrinsjater',
    backgroundColor: '#1a1a1e',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  launcherWindow.loadFile('index.html');
  launcherWindow.on('closed', () => { launcherWindow = null; });
}

async function triggerCapture(mode) {
  try {
    [launcherWindow, annotationWindow].filter(Boolean).forEach(w => w?.hide());
    app.hide();
    await new Promise((r) => setTimeout(r, 300));
    const imagePath = await captureScreen(mode);
    app.show();
    createAnnotationWindow(imagePath);
    if (launcherWindow) launcherWindow.show();
  } catch (e) {
    app.show();
    if (launcherWindow) launcherWindow.show();
  }
}

function openSettings() {
  const settingsWindow = new BrowserWindow({
    width: 420,
    height: 340,
    title: 'Настройки — Scrinsjater',
    backgroundColor: '#1a1a1e',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  settingsWindow.loadFile('settings.html');
}

app.whenReady().then(() => {
  createTray();
  createLauncherWindow();
  app.dock?.hide();
});

app.on('window-all-closed', (e) => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

ipcMain.handle('capture', async (_, mode) => {
  if (mode === 'settings') {
    openSettings();
    return;
  }
  if (launcherWindow) launcherWindow.hide();
  await triggerCapture(mode);
  if (launcherWindow) launcherWindow.show();
});
ipcMain.handle('quit', () => app.quit());

ipcMain.handle('save-screenshot', async (_, { imageData, uploadToYandex }) => {
  const defaultPath = path.join(
    os.homedir(),
    'Desktop',
    `screenshot_${new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)}.png`
  );
  const { filePath, canceled } = await dialog.showSaveDialog(annotationWindow || null, {
    defaultPath,
    filters: [{ name: 'PNG', extensions: ['png'] }],
  });
  if (canceled || !filePath) return { saved: false };

  const base64Data = imageData.replace(/^data:image\/png;base64,/, '');
  await fs.writeFile(filePath, Buffer.from(base64Data, 'base64'));

  if (uploadToYandex) {
    const token = store.get('yandexToken');
    if (token) {
      try {
        const { uploadToYandexDisk } = require('./yandex-upload');
        const url = await uploadToYandexDisk(filePath, token);
        return { saved: true, filePath, yandexUrl: url };
      } catch (err) {
        return { saved: true, filePath, yandexError: err.message };
      }
    } else {
      return { saved: true, filePath, yandexError: 'Токен не настроен' };
    }
  }
  return { saved: true, filePath };
});

ipcMain.handle('get-yandex-token', () => store.get('yandexToken'));
ipcMain.handle('set-yandex-token', (_, token) => {
  store.set('yandexToken', token || '');
});
ipcMain.handle('open-external', (_, url) => shell.openExternal(url));
