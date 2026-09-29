// Картинки студии для сайта: карточка для ссылок (og) и значки — из знака и шрифтов сайта.
//   npm i playwright && node tools/brand-assets.mjs site /tmp/out
// Потом: og-*.png → site/assets/, apple-touch-icon.png → site/, icon-*.png → site/assets/icons/,
// favicon.ico — из ico-16/32/48.png (Pillow: im48.save("favicon.ico", sizes=[(16,16),(32,32),(48,48)], append_images=[im16, im32])).
// Надпись на карточке — в функции og() ниже.
import { chromium } from 'playwright';
import fs from 'node:fs';
const site = process.argv[2], out = process.argv[3];
fs.mkdirSync(out, { recursive: true });
const font = (f) => 'data:font/woff2;base64,' + fs.readFileSync(`${site}/assets/fonts/${f}`).toString('base64');
const fav = fs.readFileSync(`${site}/favicon.svg`, 'utf8');
const markSvg = fav.replace(/<rect[^>]*\/>/, '').replace('viewBox="-2 -2 32 32"', 'viewBox="0 0 28 28"').replace(/stroke-width="1.8"/g, 'stroke-width="1.3"');
const css = `
@font-face { font-family: Kurale; src: url(${font('kurale-cyrillic-400-normal.woff2')}); unicode-range: U+0400-045F; }
@font-face { font-family: Kurale; src: url(${font('kurale-latin-400-normal.woff2')}); unicode-range: U+0000-00FF, U+2000-206F; }
@font-face { font-family: Onest; src: url(${font('onest-cyrillic-400-normal.woff2')}); unicode-range: U+0400-045F; }
@font-face { font-family: Onest; src: url(${font('onest-latin-400-normal.woff2')}); unicode-range: U+0000-00FF, U+2000-206F; }
html, body { margin: 0; }`;
// Полоса-рушник — тот же рисунок, что на сайте (site.js, BAND)
const BAND = ["..x.....x.....x..", ".x.x...xox...x.x.", "x.o.x.xo.ox.x.o.x", ".x.x...xox...x.x.", "..x.....x.....x.."];
function band(s) {
  const cols = BAND[0].length - 1; let p = '';
  for (let r = 0; r < BAND.length; r++) for (let c = 0; c < cols; c++) {
    const ch = BAND[r][c]; if (ch === '.') continue; const x = c * s, y = r * s;
    p += `<path d="M${x+1} ${y+1}L${x+s-1} ${y+s-1}M${x+s-1} ${y+1}L${x+1} ${y+s-1}" stroke="${ch === 'x' ? '#b3162f' : '#1f3c34'}" stroke-width="1.6" stroke-linecap="round"/>`;
  }
  return `<svg width="1200" height="${BAND.length * s + 4}" xmlns="http://www.w3.org/2000/svg"><defs><pattern id="b" width="${cols * s}" height="${BAND.length * s}" patternUnits="userSpaceOnUse">${p}</pattern></defs><rect y="2" width="1200" height="${BAND.length * s}" fill="url(#b)"/></svg>`;
}
const og = (name, line1, accent, sub) => `<!doctype html><html><head><meta charset="utf-8"><style>${css}
body { width: 1200px; height: 630px; background: #ecede6; position: relative; overflow: hidden; font-family: Onest; color: #1a1b1e; }
.mark { position: absolute; left: 96px; top: 118px; width: 262px; height: 262px; }
.mark svg { width: 100%; height: 100%; }
.txt { position: absolute; left: 430px; top: 104px; right: 80px; }
.name { font-family: Kurale; font-size: 118px; line-height: 1; }
.line { font-family: Kurale; font-size: 50px; line-height: 1.15; margin-top: 30px; }
.line em { font-style: normal; color: #b3162f; }
.sub { font-size: 27px; color: #4b4f4c; margin-top: 24px; line-height: 1.35; }
.band { position: absolute; left: 0; right: 0; bottom: 0; height: 104px; background: #f7f7f2; border-top: 1px solid #cfd1c6; display: flex; align-items: center; }
.url { position: absolute; right: 80px; top: 452px; font-size: 24px; color: #4b4f4c; letter-spacing: .02em; }
</style></head><body>
<div class="mark">${markSvg}</div>
<div class="txt"><div class="name">${name}</div><div class="line">${line1} <em>${accent}</em></div><div class="sub">${sub}</div></div>
<div class="url">gornitsa.games</div>
<div class="band">${band(12)}</div>
</body></html>`;
const icon = (size, pad, rounded) => `<!doctype html><html><head><style>html,body{margin:0;background:transparent}
.i{width:${size}px;height:${size}px;background:#ecede6;border-radius:${rounded ? Math.round(size * 0.1875) : 0}px;display:grid;place-items:center}
.i svg{width:${Math.round(size * (1 - 2 * pad))}px;height:${Math.round(size * (1 - 2 * pad))}px}</style></head><body>
<div class="i">${markSvg.replace(/stroke-width="1.3"/g, `stroke-width="${size <= 48 ? 1.9 : 1.5}"`)}</div></body></html>`;
const b = await chromium.launch({ ...(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {}) });
async function shot(html, w, h, file, transparent) {
  const pg = await b.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
  await pg.setContent(html, { waitUntil: 'load' });
  await pg.evaluate(() => document.fonts.ready);
  await pg.screenshot({ path: `${out}/${file}`, omitBackground: !!transparent, clip: { x: 0, y: 0, width: w, height: h } });
  await pg.close();
}
await shot(og('Горница', 'Светлая комната для', 'хороших игр', 'Спокойные, честные и понятные игры для RuStore'), 1200, 630, 'og-studio.png');
await shot(og('Gornitsa', 'A bright room for', 'good games', 'Calm, honest and clear games for RuStore'), 1200, 630, 'og-studio-en.png');
await shot(icon(180, 0.16, false), 180, 180, 'apple-touch-icon.png');          // iOS скругляет сам: фон на весь квадрат
await shot(icon(192, 0.12, true), 192, 192, 'icon-192.png', true);
await shot(icon(512, 0.12, true), 512, 512, 'icon-512.png', true);
await shot(icon(512, 0.22, false), 512, 512, 'icon-maskable-512.png');        // для масок Android: знак в безопасной зоне
for (const s of [16, 32, 48]) await shot(icon(s, 0.06, true), s, s, `ico-${s}.png`, true);
await b.close();
console.log('ok');
