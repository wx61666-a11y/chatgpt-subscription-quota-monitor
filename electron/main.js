const { app, BrowserWindow, Tray, Menu, nativeImage, ipcMain } = require('electron');
const fs = require('fs');
const path = require('path');

let mainWindow, tray, settings = { skin: 'aurora', weekly: true, fiveHour: true, text: true }, snapshot = emptySnapshot();
const minute = 60_000;

function emptySnapshot() { return { weekly: null, fiveHour: null, heatmap: Array(90).fill(0), updatedAt: null }; }
function homeCodex() { return path.join(process.env.HOME || process.env.USERPROFILE || '', '.codex'); }
function filesIn(root) { try { return fs.readdirSync(root, { withFileTypes: true }).flatMap(e => e.isDirectory() ? filesIn(path.join(root, e.name)) : e.name.endsWith('.jsonl') ? [path.join(root, e.name)] : []); } catch { return []; } }
function dateOf(value) { const d = new Date(value); return Number.isNaN(d.valueOf()) ? null : d; }
function limitsFrom(object, timestamp, out) {
  if (!object || typeof object !== 'object') return;
  if (Number.isFinite(object.window_minutes) && Number.isFinite(object.used_percent)) out.push({ minutes: object.window_minutes, used: object.used_percent, resetsAt: object.resets_at, timestamp });
  for (const value of Object.values(object)) limitsFrom(value, timestamp, out);
}
function loadSnapshot() {
  const limits = [], usage = new Map();
  for (const root of ['sessions', 'archived_sessions'].map(x => path.join(homeCodex(), x))) for (const file of filesIn(root)) {
    let text = ''; try { text = fs.readFileSync(file, 'utf8'); } catch { continue; }
    for (const line of text.split(/\r?\n/)) try {
      const item = JSON.parse(line), stamp = dateOf(item.timestamp || item.created_at || item.payload?.timestamp);
      if (!stamp) continue;
      limitsFrom(item.payload?.rate_limits || item.rate_limits, stamp, limits);
      const tokens = item.payload?.info?.last_token_usage?.total_tokens || item.payload?.info?.lastTokenUsage?.totalTokens || 0;
      const key = stamp.toISOString().slice(0, 10); usage.set(key, (usage.get(key) || 0) + Number(tokens || 0));
    } catch {}
  }
  const newest = minutes => limits.filter(x => x.minutes === minutes).sort((a,b) => b.timestamp - a.timestamp || b.used - a.used)[0] || null;
  const max = Math.max(1, ...usage.values()); const heatmap = [];
  for (let i = 89; i >= 0; i--) { const d = new Date(Date.now() - i * 86400000).toISOString().slice(0,10); heatmap.push((usage.get(d) || 0) / max); }
  return { weekly: newest(10080), fiveHour: newest(300), heatmap, updatedAt: new Date().toISOString() };
}
function arc(cx, cy, r, percent) { const a = Math.max(0, Math.min(1, percent)) * 359.99, end = -90 + a, p = d => [cx + r*Math.cos(d*Math.PI/180), cy + r*Math.sin(d*Math.PI/180)]; const [x1,y1]=p(-90),[x2,y2]=p(end); return `M ${x1} ${y1} A ${r} ${r} 0 ${a>180?1:0} 1 ${x2} ${y2}`; }
function trayImage() {
  const colors = { aurora:['#16e7ff','#3077ff','#ba52ff','#ff52d1','#72ff8d'], sunset:['#ff4f56','#ff8b36','#ffe653','#ff3a9b','#a75cff'], opal:['#8af3ef','#91c9ff','#b3a8ff','#ffabd4','#ffe783'] }[settings.skin];
  const rings = [['weekly', 17], ['fiveHour', 47]].filter(([key]) => settings[key]).map(([key,cx], i) => { const v = (snapshot[key]?.used || 0)/100; return `<circle cx="${cx}" cy="32" r="12" fill="none" stroke="white" stroke-width="4"/><path d="${arc(cx,32,12,v)}" fill="none" stroke="${colors[i*2]||colors[0]}" stroke-width="4" stroke-linecap="round"/>`; }).join('');
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">${rings || '<circle cx="32" cy="32" r="12" fill="none" stroke="white" stroke-width="4"/>'}</svg>`;
  return nativeImage.createFromDataURL(`data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}`);
}
function updateTray() { if (!tray) return; tray.setImage(trayImage()); const text = [settings.weekly && `周 ${snapshot.weekly?.used?.toFixed(0) ?? '—'}%`, settings.fiveHour && `5小时 ${snapshot.fiveHour?.used?.toFixed(0) ?? '—'}%`].filter(Boolean).join(' · '); tray.setToolTip(text || 'ChatGPT Subscription Quota Monitor'); }
function refresh() { snapshot = loadSnapshot(); updateTray(); mainWindow?.webContents.send('snapshot', snapshot); }
function createWindow() { mainWindow = new BrowserWindow({ width: 920, height: 700, minWidth: 760, minHeight: 580, backgroundColor: '#111725', webPreferences: { preload: path.join(__dirname, 'preload.js') } }); mainWindow.on('close', event => { if (!app.isQuitting) { event.preventDefault(); mainWindow.hide(); } }); mainWindow.loadFile(path.join(__dirname, 'index.html')); }
app.whenReady().then(() => { createWindow(); tray = new Tray(trayImage()); tray.on('click', () => { mainWindow.isVisible() ? mainWindow.hide() : mainWindow.show(); }); tray.setContextMenu(Menu.buildFromTemplate([{ label:'打开监控面板', click:()=>mainWindow.show() }, { type:'separator' }, { label:'退出', click:()=>app.quit() }])); refresh(); setInterval(refresh, 30_000); setInterval(updateTray, minute); });
ipcMain.handle('snapshot', () => snapshot);
ipcMain.on('refresh', refresh);
ipcMain.on('settings', (_, next) => { settings = { ...settings, ...next }; updateTray(); });
app.on('before-quit', () => { app.isQuitting = true; });
