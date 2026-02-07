const canvas = document.getElementById('canvas');
const overlay = document.getElementById('overlay');
const ctx = canvas.getContext('2d');
const overlayCtx = overlay.getContext('2d');

let img = null;
let scale = 1;
let currentTool = 'arrow';
let currentColor = '#22c55e';
let strokeWidth = 4;
let drawings = [];
let isDrawing = false;
let startX, startY;

const toolBtns = document.querySelectorAll('.tool-btn[data-tool]');
const colorBtns = document.querySelectorAll('.color-btn');
const strokeWidthInput = document.getElementById('strokeWidth');
const undoBtn = document.getElementById('undo');
const saveBtn = document.getElementById('save');
const uploadYandexCheck = document.getElementById('uploadYandex');

function drawArrow(ctx, x1, y1, x2, y2, color, w) {
  ctx.strokeStyle = color;
  ctx.fillStyle = color;
  ctx.lineWidth = w;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  ctx.beginPath();
  ctx.moveTo(x1, y1);
  ctx.lineTo(x2, y2);
  ctx.stroke();
  const angle = Math.atan2(y2 - y1, x2 - x1);
  const size = w * 3;
  ctx.beginPath();
  ctx.moveTo(x2, y2);
  ctx.lineTo(x2 - size * Math.cos(angle - Math.PI / 6), y2 - size * Math.sin(angle - Math.PI / 6));
  ctx.lineTo(x2 - size * Math.cos(angle + Math.PI / 6), y2 - size * Math.sin(angle + Math.PI / 6));
  ctx.closePath();
  ctx.fill();
}

function drawHighlight(ctx, x, y, w, h, color, strokeW) {
  ctx.strokeStyle = color;
  ctx.fillStyle = color + '40';
  ctx.lineWidth = strokeW;
  ctx.strokeRect(x, y, w, h);
  ctx.fillRect(x, y, w, h);
}

function redraw() {
  overlayCtx.clearRect(0, 0, overlay.width, overlay.height);
  drawings.forEach((d) => {
    if (d.type === 'arrow') {
      drawArrow(overlayCtx, d.x1, d.y1, d.x2, d.y2, d.color, d.width);
    } else {
      drawHighlight(overlayCtx, d.x, d.y, d.w, d.h, d.color, d.width);
    }
  });
}

overlay.addEventListener('mousedown', (e) => {
  if (!img) return;
  const rect = overlay.getBoundingClientRect();
  const sx = ((e.clientX - rect.left) / rect.width) * overlay.width;
  const sy = ((e.clientY - rect.top) / rect.height) * overlay.height;
  isDrawing = true;
  startX = sx;
  startY = sy;
});

overlay.addEventListener('mousemove', (e) => {
  if (!isDrawing || !img) return;
  const rect = overlay.getBoundingClientRect();
  const x = ((e.clientX - rect.left) / rect.width) * overlay.width;
  const y = ((e.clientY - rect.top) / rect.height) * overlay.height;
  overlayCtx.clearRect(0, 0, overlay.width, overlay.height);
  redraw();
  if (currentTool === 'arrow') {
    drawArrow(overlayCtx, startX, startY, x, y, currentColor, strokeWidth);
  } else {
    const px = Math.min(startX, x);
    const py = Math.min(startY, y);
    const pw = Math.abs(x - startX);
    const ph = Math.abs(y - startY);
    drawHighlight(overlayCtx, px, py, pw, ph, currentColor, strokeWidth);
  }
});

overlay.addEventListener('mouseup', (e) => {
  if (!isDrawing || !img) return;
  const rect = overlay.getBoundingClientRect();
  const x = ((e.clientX - rect.left) / rect.width) * overlay.width;
  const y = ((e.clientY - rect.top) / rect.height) * overlay.height;
  if (currentTool === 'arrow') {
    drawings.push({ type: 'arrow', x1: startX, y1: startY, x2: x, y2: y, color: currentColor, width: strokeWidth });
  } else {
    const px = Math.min(startX, x);
    const py = Math.min(startY, y);
    const pw = Math.abs(x - startX);
    const ph = Math.abs(y - startY);
    if (pw > 2 && ph > 2) {
      drawings.push({ type: 'highlight', x: px, y: py, w: pw, h: ph, color: currentColor, width: strokeWidth });
    }
  }
  isDrawing = false;
  redraw();
});

overlay.addEventListener('mouseleave', () => {
  if (isDrawing) {
    isDrawing = false;
    redraw();
  }
});

toolBtns.forEach((btn) => {
  btn.addEventListener('click', () => {
    toolBtns.forEach((b) => b.classList.remove('active'));
    btn.classList.add('active');
    currentTool = btn.dataset.tool;
  });
});

colorBtns.forEach((btn) => {
  btn.addEventListener('click', () => {
    colorBtns.forEach((b) => b.classList.remove('active'));
    btn.classList.add('active');
    currentColor = btn.dataset.color;
  });
});

strokeWidthInput.addEventListener('input', () => {
  strokeWidth = parseInt(strokeWidthInput.value, 10);
});

undoBtn.addEventListener('click', () => {
  drawings.pop();
  redraw();
});

function setupImage(dataUrl) {
  img = new Image();
  img.onload = () => {
    const maxW = window.innerWidth - 48;
    const maxH = window.innerHeight - 120;
    scale = Math.min(1, maxW / img.width, maxH / img.height);
    const w = Math.floor(img.width * scale);
    const h = Math.floor(img.height * scale);
    canvas.width = w;
    canvas.height = h;
    overlay.width = w;
    overlay.height = h;
    ctx.drawImage(img, 0, 0, w, h);
    drawings = [];
  };
  img.src = dataUrl;
}

async function save() {
  if (!img) return;
  const w = canvas.width;
  const h = canvas.height;
  const offscreen = document.createElement('canvas');
  offscreen.width = w;
  offscreen.height = h;
  const octx = offscreen.getContext('2d');
  octx.drawImage(canvas, 0, 0);
  drawings.forEach((d) => {
    if (d.type === 'arrow') {
      drawArrow(octx, d.x1, d.y1, d.x2, d.y2, d.color, d.width);
    } else {
      drawHighlight(octx, d.x, d.y, d.w, d.h, d.color, d.width);
    }
  });
  const dataUrl = offscreen.toDataURL('image/png');
  const result = await window.electronAPI.saveScreenshot({
    imageData: dataUrl,
    uploadToYandex: uploadYandexCheck.checked,
  });
  if (result?.saved) {
    if (result.yandexUrl) {
      alert('Сохранено и загружено на Яндекс.Диск!\n\nОткройте: ' + result.yandexUrl);
      window.electronAPI.openExternal(result.yandexUrl);
    } else if (result.yandexError) {
      alert('Сохранено: ' + result.filePath + '\n\nОшибка загрузки: ' + result.yandexError);
    } else {
      alert('Сохранено: ' + result.filePath);
    }
  }
}

saveBtn.addEventListener('click', save);

window.electronAPI.onSetImage((dataUrl) => setupImage(dataUrl));
