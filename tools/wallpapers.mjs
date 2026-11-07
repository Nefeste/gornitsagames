// Обои студии для телефона и компьютера (страница «Обои», src/wallpapers.html) — из знака,
// полосы-рушника и узора главной, кодом по сетке, как велит брендбук. Цвета — из site/assets/brand.css.
//   npm i playwright && node tools/wallpapers.mjs site/assets/wallpapers
// Пишет <обои>-phone.png (1440 × 3200), <обои>-desktop.png (3840 × 2160) и уменьшенные
// <обои>-phone-preview.png, <обои>-desktop-preview.png для страницы. Список обоев — WALLPAPERS ниже;
// новые обои — новая строка там и карточка в src/wallpapers.html и src/en/wallpapers.html.
import { chromium } from 'playwright';
import fs from 'node:fs';
const out = process.argv[2] || 'site/assets/wallpapers';
fs.mkdirSync(out, { recursive: true });

// Цвета нитей и ткани — как в brand.css (светлая и тёмная тема)
const LIGHT = { linen: '#ecede6', paper: '#f7f7f2', line: '#cfd1c6', cell: '#d9dbd1', kumach: '#b3162f', spruce: '#1f3c34', flax: '#a8904f' };
const DARK = { linen: '#111816', paper: '#18211e', line: '#2c3833', cell: '#1f2a26', kumach: '#e5566a', spruce: '#7fb3a3', flax: '#d2bd84' };

// Крестик в клетке со стороной s: две линии со скруглёнными концами, поля и толщина — как в знаке (mark.svg)
function stitch(x, y, s, color) {
  const p = s * 0.225, w = s * 0.325;
  return `<path d="M${x + p} ${y + p}L${x + s - p} ${y + s - p}M${x + s - p} ${y + p}L${x + p} ${y + s - p}" stroke="${color}" stroke-width="${w}" stroke-linecap="round" fill="none"/>`;
}

// Знак: ромб на сетке 7 × 7 — внешний ромб и середина кумачом, внутренний ромб елью
function mark(cx, cy, size, k) {
  const s = size / 7, x0 = cx - size / 2, y0 = cy - size / 2;
  let g = '';
  for (let r = 0; r < 7; r++) for (let c = 0; c < 7; c++) {
    const d = Math.abs(r - 3) + Math.abs(c - 3);
    if (d === 3 || d === 0) g += stitch(x0 + c * s, y0 + r * s, s, k.kumach);
    else if (d === 2) g += stitch(x0 + c * s, y0 + r * s, s, k.spruce);
  }
  return g;
}

// Полоса-рушник — тот же рисунок, что на сайте (site.js, BAND): на бумаге между двумя тонкими линиями
const BAND = ['..x.....x.....x..', '.x.x...xox...x.x.', 'x.o.x.xo.ox.x.o.x', '.x.x...xox...x.x.', '..x.....x.....x..'];
function band(y, w, s, k) {
  const cols = BAND[0].length - 1, rows = BAND.length, h = rows * s + s * 2, line = Math.max(2, s / 6);
  let g = `<rect x="0" y="${y}" width="${w}" height="${h}" fill="${k.paper}"/>`;
  g += `<rect x="0" y="${y}" width="${w}" height="${line}" fill="${k.line}"/><rect x="0" y="${y + h - line}" width="${w}" height="${line}" fill="${k.line}"/>`;
  const repeat = cols * s, x0 = ((w % repeat) - repeat) / 2; // узор по центру: обрезан поровну с краёв
  for (let x = x0; x < w; x += repeat)
    for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) {
      const ch = BAND[r][c];
      if (ch !== '.') g += stitch(x + c * s, y + s + r * s, s, ch === 'x' ? k.kumach : k.spruce);
    }
  return g;
}

// Узор главной (site.js, motif): 17 × 17, 0 — пусто, 1 — кумач, 2 — ель, 3 — лён
const N = 17, C = 8;
function motif(r, c) {
  const dr = Math.abs(r - C), dc = Math.abs(c - C), d = dr + dc;
  const axis = dr === 0 || dc === 0, diag = dr === dc;
  if (d <= 1) return 1;
  if (d === 2) return axis ? 1 : 3;
  if (d === 4) return 2;
  if (d === 6) return 1;
  if (d === 7) return axis ? 3 : 0;
  if (d === 8) return axis ? 1 : (diag ? 3 : 0);
  if (diag && d === 10) return 3;
  if (dr === 6 && dc === 6) return 1;
  if ((dr === 6 && Math.abs(dc - 6) === 1) || (dc === 6 && Math.abs(dr - 6) === 1)) return 2;
  if (dr === 8 && dc === 8) return 3;
  return 0;
}
// Канва: пяльцы-карточка на бумаге, клетки канвы, узор вышит крестиками
function canvas(cx, cy, size, k) {
  const pad = size * 0.07, s = (size - pad * 2) / N, x0 = cx - size / 2, y0 = cy - size / 2;
  const colors = { 1: k.kumach, 2: k.spruce, 3: k.flax };
  let g = `<rect x="${x0}" y="${y0}" width="${size}" height="${size}" rx="${size * 0.03}" fill="${k.paper}" stroke="${k.line}" stroke-width="${Math.max(2, size / 400)}"/>`;
  for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
    const x = x0 + pad + c * s, y = y0 + pad + r * s, m = motif(r, c);
    if (m) g += stitch(x, y, s, colors[m]);
    else g += `<circle cx="${x + s / 2}" cy="${y + s / 2}" r="${s * 0.09}" fill="${k.cell}"/>`;
  }
  return g;
}

// Обои: имя файла → (w, h) → SVG. Знак и узор стоят чуть выше середины: внизу телефона — значки
// и строка приложений, внизу компьютера — панель задач.
const WALLPAPERS = {
  'len': (w, h) => {
    const phone = h > w, size = phone ? w * 0.36 : h * 0.24;
    return { bg: LIGHT.linen, svg: mark(w / 2, h * (phone ? 0.44 : 0.46), size, LIGHT) };
  },
  'vecher': (w, h) => {
    const phone = h > w, size = phone ? w * 0.36 : h * 0.24;
    return { bg: DARK.linen, svg: mark(w / 2, h * (phone ? 0.44 : 0.46), size, DARK) };
  },
  'rushnik': (w, h) => {
    const phone = h > w, s = phone ? w / 40 : h / 48, bh = BAND.length * s + s * 2;
    const top = phone ? h * 0.2 : h * 0.16, bottom = phone ? h * 0.8 - bh : h * 0.78 - bh;
    return { bg: LIGHT.linen, svg: band(top, w, s, LIGHT) + band(bottom, w, s, LIGHT) + mark(w / 2, (top + bh + bottom) / 2, phone ? w * 0.2 : h * 0.16, LIGHT) };
  },
  'kanva': (w, h) => {
    const phone = h > w, size = phone ? w * 0.72 : h * 0.56;
    return { bg: LIGHT.linen, svg: canvas(w / 2, h * (phone ? 0.44 : 0.46), size, LIGHT) };
  },
  'kanva-noch': (w, h) => {
    const phone = h > w, size = phone ? w * 0.72 : h * 0.56;
    return { bg: DARK.linen, svg: canvas(w / 2, h * (phone ? 0.44 : 0.46), size, DARK) };
  },
};
const SIZES = { phone: [1440, 3200], desktop: [3840, 2160] };
const PREVIEW = { phone: 0.25, desktop: 1 / 6 }; // 360 × 800 и 640 × 360: на странице — вдвое меньше, для чётких экранов

const b = await chromium.launch({ ...(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {}) });
for (const [name, draw] of Object.entries(WALLPAPERS)) {
  for (const [kind, [w, h]] of Object.entries(SIZES)) {
    const { bg, svg } = draw(w, h);
    const doc = `<!doctype html><html><head><style>html,body{margin:0;background:${bg}}svg{display:block}</style></head><body>` +
      `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}"><rect width="${w}" height="${h}" fill="${bg}"/>${svg}</svg></body></html>`;
    for (const [suffix, scale] of [['', 1], ['-preview', PREVIEW[kind]]]) {
      const pg = await b.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: scale });
      await pg.setContent(doc, { waitUntil: 'load' });
      await pg.screenshot({ path: `${out}/${name}-${kind}${suffix}.png`, clip: { x: 0, y: 0, width: w, height: h } });
      await pg.close();
    }
  }
}
await b.close();
console.log('ok');
