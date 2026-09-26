/* Горница — узор-раскраска на главной, орнаментальная полоса и копирование почты */
(function () {
  "use strict";

  var N = 17, C = 8;

  // Цвет клетки узора: 0 — пусто, 1 — красная нить, 2 — еловая, 3 — льняная.
  function motif(r, c) {
    var dr = Math.abs(r - C), dc = Math.abs(c - C), d = dr + dc;
    var axis = dr === 0 || dc === 0, diag = dr === dc;
    if (d <= 1) return 1;
    if (d === 2) return axis ? 1 : 3;
    if (d === 4) return 2;
    if (d === 6) return 1;
    if (d === 7) return axis ? 3 : 0;
    if (d === 8) return axis ? 1 : (diag ? 3 : 0);
    if (diag && d === 10) return 3;
    // малые ромбы в углах
    if (dr === 6 && dc === 6) return 1;
    if ((dr === 6 && Math.abs(dc - 6) === 1) || (dc === 6 && Math.abs(dr - 6) === 1)) return 2;
    if (dr === 8 && dc === 8) return 3;
    return 0;
  }

  // Детерминированный выбор клеток с номерами
  function rand(seed) {
    var s = seed >>> 0;
    return function () { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
  }

  // Надписи на языке страницы (<html lang="ru"> или lang="en")
  var EN = (document.documentElement.lang || "").slice(0, 2) === "en";
  var T = EN ? {
    names: { 1: "red", 2: "spruce", 3: "flax" },
    cell: function (r, c, v) { return "Cell " + r + "-" + c + ", thread " + v + " (" + T.names[v] + ")"; },
    pick: "Pick a thread and fill in the numbered cells.",
    wrong: function (v) { return "This cell takes thread " + v + " (" + T.names[v] + "). Pick it below."; },
    done: "Pattern complete. That’s how our color-by-number game Uzory will work.",
    copy: "Copy", copied: "Copied", selected: "Selected — press Ctrl+C"
  } : {
    names: { 1: "красная", 2: "еловая", 3: "льняная" },
    cell: function (r, c, v) { return "Клетка " + r + "-" + c + ", нить " + v + " (" + T.names[v] + ")"; },
    pick: "Выберите нить и закрасьте клетки с номерами.",
    wrong: function (v) { return "Эта клетка под нить " + v + " (" + T.names[v] + "). Выберите её ниже."; },
    done: "Узор готов. Так будет устроена наша раскраска «Узоры».",
    copy: "Скопировать", copied: "Скопировано", selected: "Выделено, нажмите Ctrl+C"
  };

  function buildCanvas(root) {
    var grid = root.querySelector(".canvas");
    var left = root.querySelector("[data-left]");
    var note = root.querySelector("[data-note]");
    var buttons = root.querySelectorAll(".thread");
    if (!grid) return;

    var current = 1, remaining = 0, rnd = rand(17);
    var frag = document.createDocumentFragment();

    for (var r = 0; r < N; r++) {
      for (var c = 0; c < N; c++) {
        var v = motif(r, c);
        var cell = document.createElement("button");
        cell.type = "button";
        cell.className = "cell";
        cell.tabIndex = -1;
        if (v) {
          if (rnd() < 0.2) {
            cell.dataset.num = String(v);
            cell.textContent = String(v);
            cell.tabIndex = 0;
            cell.setAttribute("aria-label", T.cell(r + 1, c + 1, v));
            remaining++;
          } else {
            cell.className += " st c" + v;
            cell.setAttribute("aria-hidden", "true");
          }
        } else {
          cell.setAttribute("aria-hidden", "true");
        }
        frag.appendChild(cell);
      }
    }
    grid.appendChild(frag);

    function update() {
      if (left) left.textContent = String(remaining);
      if (note && remaining === 0) {
        note.textContent = T.done;
      }
    }
    update();

    function select(v) {
      current = v;
      buttons.forEach(function (b) { b.setAttribute("aria-pressed", String(Number(b.dataset.thread) === v)); });
    }
    buttons.forEach(function (b) {
      b.addEventListener("click", function () { select(Number(b.dataset.thread)); });
    });
    select(1);

    grid.addEventListener("click", function (e) {
      var cell = e.target.closest(".cell[data-num]");
      if (!cell) return;
      var v = Number(cell.dataset.num);
      if (v !== current) {
        cell.classList.remove("miss");
        void cell.offsetWidth;
        cell.classList.add("miss");
        if (note) note.textContent = T.wrong(v);
        return;
      }
      delete cell.dataset.num;
      cell.textContent = "";
      cell.tabIndex = -1;
      cell.setAttribute("aria-hidden", "true");
      cell.className = "cell st pop c" + v;
      remaining--;
      if (note && remaining > 0) note.textContent = T.pick;
      update();
    });
  }

  // Полоса-рушник: повторяющийся узор из крестиков, цвета берутся из токенов темы
  var BAND = [
    "..x.....x.....x..",
    ".x.x...xox...x.x.",
    "x.o.x.xo.ox.x.o.x",
    ".x.x...xox...x.x.",
    "..x.....x.....x.."
  ];
  function buildBand(svg) {
    var ns = "http://www.w3.org/2000/svg";
    var cols = BAND[0].length - 1, rows = BAND.length, s = 6;
    var id = "band-" + Math.random().toString(36).slice(2, 8);
    var defs = document.createElementNS(ns, "defs");
    var pat = document.createElementNS(ns, "pattern");
    pat.setAttribute("id", id);
    pat.setAttribute("width", String(cols * s));
    pat.setAttribute("height", String(rows * s));
    pat.setAttribute("patternUnits", "userSpaceOnUse");
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        var ch = BAND[r][c];
        if (ch === ".") continue;
        var x = c * s, y = r * s;
        var g = document.createElementNS(ns, "path");
        g.setAttribute("d", "M" + (x + 1) + " " + (y + 1) + "L" + (x + s - 1) + " " + (y + s - 1) + "M" + (x + s - 1) + " " + (y + 1) + "L" + (x + 1) + " " + (y + s - 1));
        g.setAttribute("stroke", ch === "x" ? "var(--kumach)" : "var(--spruce)");
        g.setAttribute("stroke-width", "1.6");
        g.setAttribute("stroke-linecap", "round");
        g.setAttribute("fill", "none");
        pat.appendChild(g);
      }
    }
    defs.appendChild(pat);
    svg.appendChild(defs);
    var rect = document.createElementNS(ns, "rect");
    rect.setAttribute("width", "100%");
    rect.setAttribute("height", String(rows * s));
    rect.setAttribute("y", "2");
    rect.setAttribute("fill", "url(#" + id + ")");
    svg.appendChild(rect);
  }

  function buildCopy(btn) {
    btn.addEventListener("click", function () {
      var target = document.getElementById(btn.dataset.copy);
      if (!target) return;
      var text = target.textContent.trim();
      var done = function () {
        btn.textContent = T.copied;
        setTimeout(function () { btn.textContent = T.copy; }, 1800);
      };
      var fallback = function () {
        var range = document.createRange();
        range.selectNodeContents(target);
        var sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
        btn.textContent = T.selected;
      };
      try {
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(done, fallback);
        } else { fallback(); }
      } catch (e) { fallback(); }
    });
  }

  function init() {
    document.querySelectorAll("[data-hoop]").forEach(buildCanvas);
    document.querySelectorAll("svg.band").forEach(buildBand);
    document.querySelectorAll("[data-copy]").forEach(buildCopy);
    var y = document.querySelector("[data-year]");
    if (y) y.textContent = String(new Date().getFullYear());
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
