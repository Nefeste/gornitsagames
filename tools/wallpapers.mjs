// Обои студии для телефона и компьютера (страница «Обои», src/wallpapers.html): знак, полоса-рушник
// и узор главной, вышитые кодом по одной сетке на всё полотно, как велит брендбук. Цвета — только
// из site/assets/brand.css (светлая и тёмная тема), заливки плоские, без градиентов и теней.
//   npm i playwright && node tools/wallpapers.mjs site/assets/wallpapers
// Пишет <обои>-phone.png (1440 × 3200), <обои>-desktop.png (3840 × 2160) и уменьшенные
// <обои>-phone-preview.png, <обои>-desktop-preview.png для страницы. Список обоев — WALLPAPERS ниже;
// новые обои — новая строка там и карточка в src/wallpapers.html и src/en/wallpapers.html.
//
// Как устроен рисунок. Всё полотно — канва: сетка клеток одного размера, в углах клеток — дырочки
// цвета --cell. Крестик — две нити в клетке: нижняя идёт «/», верхняя «\» и лежит поверх —
// под ней просвет цвета ткани, как у настоящего стежка. Мотивы — из северной вышивки: ромбы,
// ёлочки (зигзаг), кресты, ступени; все стоят на той же сетке. Знак — 7 × 7 клеток, без поворота
// и чужих цветов, с охранным полем в клетку (брендбук). Верх телефона (часы, строка состояния)
// и низ (значки, полоса «домой») и низ экрана компьютера (панель задач) остаются спокойными.
import { chromium } from 'playwright';
import fs from 'node:fs';
const out = process.argv[2] || 'site/assets/wallpapers';
fs.mkdirSync(out, { recursive: true });

// Цвета нитей и ткани — как в brand.css (светлая и тёмная тема)
const LIGHT = { linen: '#ecede6', paper: '#f7f7f2', line: '#cfd1c6', cell: '#d9dbd1', kumach: '#b3162f', spruce: '#1f3c34', flax: '#a8904f' };
const DARK = { linen: '#111816', paper: '#18211e', line: '#2c3833', cell: '#1f2a26', kumach: '#e5566a', spruce: '#7fb3a3', flax: '#d2bd84' };
const K = 'kumach', S = 'spruce', F = 'flax';

// Полотно: клетка s, середина клетки (0, 0) — в точке (cx, cy) экрана. Стежки — в карте «i,j» → нить.
function scene(w, h, s, cy, k) {
  return { w, h, s, cx: w / 2, cy, k, st: new Map(), extra: '' };
}
const put = (sc, i, j, t) => { if (t) sc.st.set(i + ',' + j, t); };
const cellX = (sc, i) => sc.cx + (i - 0.5) * sc.s; // левый верхний угол клетки
const cellY = (sc, j) => sc.cy + (j - 0.5) * sc.s;
// Сколько клеток помещается от середины до края (с запасом на обрезанные)
const halfW = (sc) => Math.ceil(sc.cx / sc.s) + 1;
const halfH = (sc) => Math.ceil(Math.max(sc.cy, sc.h - sc.cy) / sc.s) + 1;
const jAt = (sc, y) => Math.round((y - sc.cy) / sc.s); // ближайшая клетка к высоте y

// Мотив из строк: '.' — пусто, буквы — нити (см. THREAD). Ставится левым верхним углом в (i0, j0).
const THREAD = { x: K, o: S, f: F };
function place(sc, rows, i0, j0, map = THREAD) {
  rows.forEach((row, r) => { for (let c = 0; c < row.length; c++) put(sc, i0 + c, j0 + r, map[row[c]]); });
}
// Мотив по формуле: fn(r, c) → нить или null, в прямоугольнике rows × cols с углом в (i0, j0)
function fill(sc, i0, j0, cols, rows, fn) {
  for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) put(sc, i0 + c, j0 + r, fn(r, c));
}
// Полоса на всю ширину: период period клеток, строки rows, верх в клетке j0. Узор по центру:
// обрезан поровну с краёв.
function strip(sc, j0, rows, period, fn, phase = 0) {
  const n = Math.ceil((halfW(sc) * 2 + period) / period) + 1;
  const i0 = -Math.floor(n / 2) * period + phase;
  for (let c = 0; c < n * period; c++) for (let r = 0; r < rows; r++) put(sc, i0 + c, j0 + r, fn(r, c % period));
}
// Знак: ромб на сетке 7 × 7 — внешний ромб и середина кумачом, внутренний ромб елью (brand/mark.svg)
function mark(sc, i0 = -3, j0 = -3) {
  fill(sc, i0, j0, 7, 7, (r, c) => { const d = Math.abs(r - 3) + Math.abs(c - 3); return d === 3 || d === 0 ? K : d === 2 ? S : null; });
}
// Полоса-рушник — тот же рисунок, что на сайте (site.js, BAND); период 16 клеток, 5 строк
const BAND = ['..x.....x.....x.', '.x.x...xox...x.x', 'x.o.x.xo.ox.x.o.', '.x.x...xox...x.x', '..x.....x.....x.'];
const band = (r, c) => THREAD[BAND[r][c]];
// Ёлочка: зигзаг в 3 строки, период 4
const zigzag = (t) => (r, c) => ((c % 4 === 0 && r === 0) || (c % 2 === 1 && r === 1) || (c % 4 === 2 && r === 2)) ? t : null;
// Цепь ромбов: 9 строк, период 10 — ромб кумачом с еловой серединой и льняными точками, между ромбами
// льняная связка и еловые ёлочки сверху и снизу
function chain(r, c) {
  const dr = Math.abs(r - 4), dc = Math.abs(c - 4), d = dr + dc;
  if (d === 4) return K;
  if (d === 0) return K;
  if (d === 1) return S;
  if (d === 2 && (dr === 0 || dc === 0)) return F;
  if (c === 9 && r === 4) return F;
  if ((r === 0 || r === 8) && c === 9) return S;
  if ((r === 1 || r === 7) && (c === 8 || c === 0)) return S;
  return null;
}
// Узор главной (site.js, motif): 17 × 17, кумач, ель и лён
function motif(r, c) {
  const C = 8, dr = Math.abs(r - C), dc = Math.abs(c - C), d = dr + dc;
  const axis = dr === 0 || dc === 0, diag = dr === dc;
  if (d <= 1) return K;
  if (d === 2) return axis ? K : F;
  if (d === 4) return S;
  if (d === 6) return K;
  if (d === 7) return axis ? F : null;
  if (d === 8) return axis ? K : (diag ? F : null);
  if (diag && d === 10) return F;
  if (dr === 6 && dc === 6) return K;
  if ((dr === 6 && Math.abs(dc - 6) === 1) || (dc === 6 && Math.abs(dr - 6) === 1)) return S;
  if (dr === 8 && dc === 8) return F;
  return null;
}
// Контур ромба радиусом n клеток вокруг (0, 0): ступени — лесенка стежков по диагоналям
function lozenge(sc, n, t, ci = 0, cj = 0) {
  for (let j = -n; j <= n; j++) for (let i = -n; i <= n; i++) if (Math.abs(i) + Math.abs(j) === n) put(sc, ci + i, cj + j, t);
}
// Волна-ёлочка в две строки: стежки то выше, то ниже — по горизонтали (от i1 до i2, строки j и j + 1)
// и по вертикали (от j1 до j2, столбцы i и i + 1)
function wave(sc, i1, i2, j, t) { for (let i = i1; i <= i2; i++) put(sc, i, j + Math.abs(i - i1) % 2, t); }
function waveV(sc, j1, j2, i, t) { for (let j = j1; j <= j2; j++) put(sc, i + Math.abs(j - j1) % 2, j, t); }
// Крестик «+» из пяти клеток
function cross(sc, i, j, t, arm = 1) {
  put(sc, i, j, t);
  for (let a = 1; a <= arm; a++) { put(sc, i + a, j, t); put(sc, i - a, j, t); put(sc, i, j + a, t); put(sc, i, j - a, t); }
}

// Рисунок в SVG: дырочки канвы, затем нижние нити всех стежков, затем просветы и верхние нити
function render(sc) {
  const { w, h, s, k } = sc, p = s * 0.225, wd = s * 0.325; // поля и толщина — как в знаке (mark.svg)
  let g = `<rect width="${w}" height="${h}" fill="${k.linen}"/>` + sc.extra;
  // Канва: дырочки в углах клеток
  const hw = halfW(sc), hh = halfH(sc);
  let dots = '';
  for (let j = -hh; j <= hh; j++) for (let i = -hw; i <= hw; i++) dots += `M${(cellX(sc, i)).toFixed(1)} ${(cellY(sc, j)).toFixed(1)}h0`;
  g += `<path d="${dots}" stroke="${k.cell}" stroke-width="${(s * 0.15).toFixed(2)}" stroke-linecap="round" fill="none"/>`;
  const under = {}, over = {}, halo = [];
  for (const [key, t] of sc.st) {
    const [i, j] = key.split(',').map(Number), x = cellX(sc, i), y = cellY(sc, j);
    const c = k[t];
    (under[c] = under[c] || []).push(`M${(x + p).toFixed(1)} ${(y + s - p).toFixed(1)}L${(x + s - p).toFixed(1)} ${(y + p).toFixed(1)}`);
    const o = `M${(x + p).toFixed(1)} ${(y + p).toFixed(1)}L${(x + s - p).toFixed(1)} ${(y + s - p).toFixed(1)}`;
    halo.push(o);
    (over[c] = over[c] || []).push(o);
  }
  const path = (d, c, width) => `<path d="${d.join('')}" stroke="${c}" stroke-width="${width.toFixed(2)}" stroke-linecap="round" fill="none"/>`;
  for (const c in under) g += path(under[c], c, wd);
  if (halo.length) g += path(halo, k.linen, wd * 1.5);
  for (const c in over) g += path(over[c], c, wd);
  return g;
}

// Обои: имя файла → (w, h, цвета) → сцена; обои «-noch» и «vecher» — в цветах тёмной темы. phone — экран стоймя.
// Телефон: верх 12 % (часы, строка состояния) и низ 12 % (значки, полоса «домой») спокойные; компьютер: низ 8 % (панель задач).
// Проверка: node tools/wallpapers.mjs <папка> [имя,имя] — только названные обои.
const WALLPAPERS = {
  // Знак в большом льняном ромбе на канве: ромб — лесенка в две клетки, на углах еловые кресты;
  // на компьютере от ромба к краям — льняная нить, как рушник сквозь медальон
  'len': (w, h, k) => {
    const phone = h > w, s = 60, sc = scene(w, h, s, Math.round(h * (phone ? 0.46 : 0.47)), k);
    mark(sc);
    const n = phone ? 8 : 9;
    lozenge(sc, n, F); lozenge(sc, n + 1, F);
    for (const [i, j] of phone ? [[0, n + 3], [0, -n - 3]] : [[n + 3, 0], [-n - 3, 0], [0, n + 3], [0, -n - 3]]) cross(sc, i, j, S);
    if (!phone) { const hw = halfW(sc); for (let i = n + 6; i <= hw; i++) { put(sc, i, 0, F); put(sc, -i, 0, F); } }
    return sc;
  },
  'vecher': (w, h, k) => WALLPAPERS.len(w, h, k),
  // Рушник: полотенце бумажного цвета поперёк экрана — ёлочки, полоса сайта и цепь ромбов,
  // в середине цепи вместо ромба — знак с охранным полем в клетку
  'rushnik': (w, h, k) => {
    const phone = h > w, s = phone ? 48 : 36, sc = scene(w, h, s, Math.round(h * (phone ? 0.62 : 0.58)), k);
    const rows = [[3, zigzag(F), 4, 2], [1], [5, band, 16, 0], [1], [9, chain, 10, -4], [1], [5, band, 16, 0], [1], [3, zigzag(F), 4, 2]];
    const total = rows.reduce((a, r) => a + r[0], 0);
    const j0 = -Math.floor(total / 2), pad = 2;
    const top = cellY(sc, j0 - pad), bottom = cellY(sc, j0 + total + pad);
    const line = Math.max(2, s / 12);
    sc.extra = `<rect x="0" y="${top}" width="${w}" height="${bottom - top}" fill="${k.paper}"/>` +
      `<rect x="0" y="${top}" width="${w}" height="${line}" fill="${k.line}"/><rect x="0" y="${bottom - line}" width="${w}" height="${line}" fill="${k.line}"/>`;
    let j = j0;
    for (const [n, fn, period, phase] of rows) {
      if (fn) strip(sc, j, n, period, fn, phase);
      if (fn === chain) { // окно под знак: средний ромб, связки и ёлочки рядом убираются, знак — с охранным полем
        for (let a = -5; a <= 5; a++) for (let b = 0; b < 9; b++) sc.st.delete(a + ',' + (j + b));
        for (const [a, b] of [[6, 1], [6, 7], [-6, 1], [-6, 7]]) sc.st.delete(a + ',' + (j + b));
        mark(sc, -3, j + 1);
      }
      j += n;
    }
    return sc;
  },
  'rushnik-noch': (w, h, k) => WALLPAPERS.rushnik(w, h, k),
  // Канва: узор главной крупно в рамке-ёлочке; на компьютере рамка шире, по бокам — ромбы из цепи
  'kanva': (w, h, k) => {
    const phone = h > w, s = 56, sc = scene(w, h, s, Math.round(h * (phone ? 0.46 : 0.48)), k);
    fill(sc, -8, -8, 17, 17, motif);
    const ni = phone ? 11 : 26, nj = phone ? 11 : 13;
    wave(sc, -ni, ni, nj, F); wave(sc, -ni, ni, -nj - 1, F);
    waveV(sc, -nj, nj, -ni - 1, F); waveV(sc, -nj, nj, ni, F);
    if (!phone) for (const ci of [-16, 16]) fill(sc, ci - 4, -4, 9, 9, chain);
    return sc;
  },
  'kanva-noch': (w, h, k) => WALLPAPERS.kanva(w, h, k),
  // Скатерть: ромбическая сетка льняной нитью на всё полотно, в узлах еловые крестики, в ромбах по кумачовому стежку
  'skatert': (w, h, k) => {
    const phone = h > w, s = phone ? 40 : 30, P = phone ? 14 : 16, sc = scene(w, h, s, Math.round(h / 2), k);
    const hw = halfW(sc), hh = halfH(sc), m = (v) => ((v % P) + P) % P;
    fill(sc, -hw, -hh, hw * 2 + 1, hh * 2 + 1, (r, c) => {
      const i = c - hw, j = r - hh, a = m(i + j), b = m(i - j);
      if ((a === 0 && (b === 0 || b === 2 || b === P - 2)) || (b === 0 && (a === 2 || a === P - 2))) return S;
      if (a === 0 || b === 0) return F;
      return a === P / 2 && b === P / 2 ? K : null;
    });
    return sc;
  },
  'skatert-noch': (w, h, k) => WALLPAPERS.skatert(w, h, k),
};
const SIZES = { phone: [1440, 3200], desktop: [3840, 2160] };
const PREVIEW = { phone: 0.25, desktop: 1 / 6 }; // 360 × 800 и 640 × 360: на странице — вдвое меньше, для чётких экранов
const only = process.argv[3] ? process.argv[3].split(',') : null;

const b = await chromium.launch({ ...(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {}) });
for (const [name, draw] of Object.entries(WALLPAPERS)) {
  if (only && !only.includes(name)) continue;
  const k = name.endsWith('-noch') || name === 'vecher' ? DARK : LIGHT;
  for (const [kind, [w, h]] of Object.entries(SIZES)) {
    const svg = render(draw(w, h, k));
    const doc = `<!doctype html><html><head><style>html,body{margin:0;background:${k.linen}}svg{display:block}</style></head><body>` +
      `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${svg}</svg></body></html>`;
    for (const [suffix, scale] of [['', 1], ['-preview', PREVIEW[kind]]]) {
      const pg = await b.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: scale });
      await pg.setContent(doc, { waitUntil: 'load' });
      await pg.screenshot({ path: `${out}/${name}-${kind}${suffix}.png`, clip: { x: 0, y: 0, width: w, height: h } });
      await pg.close();
    }
  }
  console.log(name);
}
await b.close();
console.log('ok');
