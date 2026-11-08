/* Горница — узор-раскраска на главной, орнаментальная полоса, копирование почты, снимки крупно,
   шапка при прокрутке, появление карточек, слова пословицы, петли игр в карточках и плеер роликов по нажатию.
   Сайт целиком работает и без этого скрипта. */
(function () {
  "use strict";

  // Стили, которые есть только со скриптом (появление карточек при прокрутке), ждут этот класс:
  // без скрипта страница целиком видна сразу.
  document.documentElement.classList.add("js");

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
    copy: "Copy", copied: "Copied", selected: "Selected — press Ctrl+C",
    zoom: "Screenshot", close: "Close", prev: "Previous screenshot", next: "Next screenshot",
    bigger: "Actual size", fit: "Fit to screen", of: " of ",
    hoop: "Try the cross-stitch demo"
  } : {
    names: { 1: "красная", 2: "еловая", 3: "льняная" },
    cell: function (r, c, v) { return "Клетка " + r + "-" + c + ", нить " + v + " (" + T.names[v] + ")"; },
    pick: "Выберите нить и закрасьте клетки с номерами.",
    wrong: function (v) { return "Эта клетка под нить " + v + " (" + T.names[v] + "). Выберите её ниже."; },
    done: "Узор готов. Так будет устроена наша раскраска «Узоры».",
    copy: "Скопировать", copied: "Скопировано", selected: "Выделено, нажмите Ctrl+C",
    zoom: "Снимок экрана", close: "Закрыть", prev: "Предыдущий снимок", next: "Следующий снимок",
    bigger: "Исходный размер", fit: "Вписать в экран", of: " из ",
    hoop: "Вышить узор-пример"
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
            // готовые стежки прорастают от середины узора к краям (site.css, .grow)
            cell.className += " st grow c" + v;
            cell.style.setProperty("--i", String(Math.abs(r - C) + Math.abs(c - C)));
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

  // Брендбук: значения токенов под образцами цветов — из стилей страницы (brand.css), в текущей теме.
  function fillTokens() {
    var cs = getComputedStyle(document.documentElement);
    document.querySelectorAll("[data-token]").forEach(function (el) {
      var v = cs.getPropertyValue(el.dataset.token).trim();
      if (v) el.textContent = el.dataset.token + ": " + v;
    });
  }

  // Снимки игр крупно. Нажатие на снимок открывает крупную картинку (…-full.webp) во весь экран,
  // чтобы читался мелкий текст игры. Нажатие на снимок — исходный размер и обратно; стрелки,
  // кнопки и свайп — соседние снимки; Esc, «Назад» телефона и нажатие мимо снимка — закрыть.
  // Без JS или без <dialog> ссылка просто открывает крупную картинку.
  function buildZoom(section) {
    var links = [].slice.call(section.querySelectorAll("a.shot"));
    if (!links.length || typeof HTMLDialogElement !== "function") return;

    var icon = function (d) {
      return '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="' + d + '"/></svg>';
    };
    var LENS = "M10.5 4a6.5 6.5 0 1 1 0 13a6.5 6.5 0 0 1 0-13zM15.3 15.3L20 20M7.5 10.5h6";
    var dlg = document.createElement("dialog");
    dlg.className = "zoom";
    dlg.setAttribute("aria-label", T.zoom);
    dlg.innerHTML =
      '<div class="zoom-frame"><img alt="" draggable="false"></div>' +
      '<div class="zoom-bar"><span class="zoom-count"></span>' +
      '<button type="button" class="zoom-btn" data-z="size">' + icon(LENS) + "</button>" +
      '<button type="button" class="zoom-btn" data-z="close" autofocus>' + icon("M6 6l12 12M18 6L6 18") + "</button></div>" +
      '<p class="zoom-cap"></p>' +
      '<button type="button" class="zoom-btn zoom-nav" data-z="prev">' + icon("M15 5l-7 7 7 7") + "</button>" +
      '<button type="button" class="zoom-btn zoom-nav" data-z="next">' + icon("M9 5l7 7-7 7") + "</button>";
    document.body.appendChild(dlg);

    var frame = dlg.querySelector(".zoom-frame"), img = frame.querySelector("img");
    var count = dlg.querySelector(".zoom-count"), cap = dlg.querySelector(".zoom-cap");
    var btn = {};
    dlg.querySelectorAll("[data-z]").forEach(function (b) { btn[b.dataset.z] = b; });
    function name(b, text) { b.setAttribute("aria-label", text); b.title = text; }
    name(btn.close, T.close); name(btn.prev, T.prev); name(btn.next, T.next);
    btn.prev.hidden = btn.next.hidden = links.length < 2;

    var i = 0, full = false, pushed = false;

    // Размер: вписать в экран (не крупнее самой картинки) или исходный — пиксель в пиксель.
    function layout(x, y) {
      var d = (links[i].dataset.size || "").split("x");
      var nw = +d[0] || img.naturalWidth, nh = +d[1] || img.naturalHeight;
      if (!nw || !nh) return;
      var cs = getComputedStyle(frame);  // поля рамки — место под кнопками и подписью
      var px = parseFloat(cs.paddingLeft) + parseFloat(cs.paddingRight);
      var py = parseFloat(cs.paddingTop) + parseFloat(cs.paddingBottom);
      var k = Math.min((frame.clientWidth - px) / nw, (frame.clientHeight - py) / nh, 1);
      var grow = k < 0.97;
      if (!grow) full = false;
      var s = full ? 1 : k;
      img.style.width = Math.round(nw * s) + "px";
      img.style.height = Math.round(nh * s) + "px";
      frame.classList.toggle("is-full", full);
      frame.classList.toggle("no-grow", !grow);
      btn.size.hidden = !grow;
      btn.size.setAttribute("aria-pressed", String(full));
      btn.size.querySelector("path").setAttribute("d", full ? LENS : LENS + "M10.5 7.5v6");
      name(btn.size, full ? T.fit : T.bigger);
      if (full && x != null) {  // та точка снимка, куда нажали, — посередине экрана
        frame.scrollLeft = parseFloat(cs.paddingLeft) + x * nw - frame.clientWidth / 2;
        frame.scrollTop = parseFloat(cs.paddingTop) + y * nh - frame.clientHeight / 2;
      }
    }

    function show(n) {
      i = (n + links.length) % links.length;
      var a = links[i], small = a.querySelector("img"), fig = a.closest("figure");
      var c = fig && fig.querySelector("figcaption");
      full = false;
      img.alt = small ? small.alt : "";
      // Пока грузится крупная, видна уже загруженная маленькая — того же размера на экране.
      img.src = small && small.complete && small.naturalWidth ? (small.currentSrc || small.src) : a.href;
      var big = new Image();
      big.onload = function () { if (links[i] === a) img.src = a.href; };
      big.src = a.href;
      cap.textContent = c ? c.textContent : "";
      count.textContent = links.length > 1 ? (i + 1) + T.of + links.length : "";
      layout();
      frame.scrollTop = frame.scrollLeft = 0;
      [i + 1, i - 1].forEach(function (m) { new Image().src = links[(m + links.length) % links.length].href; });
    }

    function open(n) {
      show(n);
      if (dlg.open) return;
      dlg.showModal();
      document.documentElement.classList.add("zoom-open");
      layout();
      try { history.pushState({ zoom: true }, ""); pushed = true; } catch (e) { pushed = false; }
    }

    dlg.addEventListener("close", function () {
      document.documentElement.classList.remove("zoom-open");
      img.removeAttribute("src");
      links[i].focus();
      if (pushed) { pushed = false; history.back(); }
    });
    // «Назад» на телефоне закрывает снимок, а не уводит со страницы.
    window.addEventListener("popstate", function () {
      if (dlg.open) { pushed = false; dlg.close(); }
    });
    window.addEventListener("resize", function () { if (dlg.open) layout(); });

    links.forEach(function (a, n) {
      a.addEventListener("click", function (e) {
        if (e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;  // новая вкладка — как обычно
        e.preventDefault();
        open(n);
      });
    });
    btn.close.addEventListener("click", function () { dlg.close(); });
    btn.prev.addEventListener("click", function () { show(i - 1); });
    btn.next.addEventListener("click", function () { show(i + 1); });
    btn.size.addEventListener("click", function () { full = !full; layout(0.5, 0.5); });

    // Мышь в исходном размере: снимок тянется. Палец вписанный снимок листает свайпом.
    var drag = null, moved = false;
    frame.addEventListener("pointerdown", function (e) {
      moved = false;
      if (e.isPrimary) drag = { x: e.clientX, y: e.clientY, l: frame.scrollLeft, t: frame.scrollTop, mouse: e.pointerType === "mouse" };
    });
    frame.addEventListener("pointermove", function (e) {
      if (!drag) return;
      var dx = e.clientX - drag.x, dy = e.clientY - drag.y;
      if (Math.abs(dx) + Math.abs(dy) > 6) moved = true;
      if (drag.mouse && full) { frame.scrollLeft = drag.l - dx; frame.scrollTop = drag.t - dy; }
    });
    frame.addEventListener("pointerup", function (e) {
      if (!drag) return;
      var dx = e.clientX - drag.x, dy = e.clientY - drag.y, touch = !drag.mouse;
      drag = null;
      if (touch && !full && Math.abs(dx) > 50 && Math.abs(dx) > 1.5 * Math.abs(dy)) show(i + (dx < 0 ? 1 : -1));
    });
    frame.addEventListener("pointercancel", function () { drag = null; });
    frame.addEventListener("click", function (e) {
      if (moved) return;
      if (e.target !== img) { dlg.close(); return; }  // мимо снимка — закрыть
      if (frame.classList.contains("no-grow")) return;
      var r = img.getBoundingClientRect();
      full = !full;
      layout((e.clientX - r.left) / r.width, (e.clientY - r.top) / r.height);
    });
    dlg.addEventListener("keydown", function (e) {
      if (full && e.key.indexOf("Arrow") === 0) return;  // в исходном размере стрелки двигают снимок
      if (e.key === "ArrowRight") { show(i + 1); e.preventDefault(); }
      else if (e.key === "ArrowLeft") { show(i - 1); e.preventDefault(); }
    });
  }

  // На телефоне узор-пример на главной свёрнут в кнопку под первым экраном: так игры ближе.
  // Ссылка на #hoop (карточка «Узоров») и кнопка его разворачивают.
  function foldHoop(hoop) {
    if (!window.matchMedia || !window.matchMedia("(max-width: 640px)").matches) return;
    var actions = document.querySelector(".hero .actions");
    if (!actions) return;
    var btn = document.createElement("button");
    btn.type = "button";
    btn.className = "btn btn-ghost hoop-open";
    btn.textContent = T.hoop;
    btn.setAttribute("aria-controls", hoop.id);
    btn.setAttribute("aria-expanded", "false");
    actions.insertAdjacentElement("afterend", btn);
    hoop.classList.add("is-folded");
    function unfold(scroll) {
      hoop.classList.remove("is-folded");
      btn.hidden = true;
      btn.setAttribute("aria-expanded", "true");
      if (scroll) hoop.scrollIntoView({ block: "start" });
    }
    btn.addEventListener("click", function () { unfold(true); });
    document.addEventListener("click", function (e) {
      var a = e.target.closest && e.target.closest('a[href$="#' + hoop.id + '"]');
      if (a && hoop.classList.contains("is-folded")) { e.preventDefault(); unfold(true); history.replaceState(null, "", "#" + hoop.id); }
    });
    if (location.hash === "#" + hoop.id) unfold(true);
  }

  // Шторка перед снимками «Анамнеза»: ответ «Мне есть 16» помнит этот браузер; без хранилища — спросит снова.
  function buildVeil(veil) {
    var key = "veil:" + veil.getAttribute("data-veil");
    try { if (localStorage.getItem(key) === "1") veil.open = true; } catch (e) {}
    veil.addEventListener("toggle", function () {
      if (veil.open) { try { localStorage.setItem(key, "1"); } catch (e) {} }
    });
  }

  // Шапка: пока страница наверху, она сливается с фоном; сдвинулась — линия и тень (site.css, .is-scrolled).
  // Следим не за прокруткой, а за меткой в 4 px над шапкой: ушла с экрана — страница сдвинута.
  function watchHeader(header) {
    if (!("IntersectionObserver" in window)) return;
    var mark = document.createElement("div");
    mark.className = "scroll-mark";
    mark.setAttribute("aria-hidden", "true");
    header.parentNode.insertBefore(mark, header);
    new IntersectionObserver(function (entries) {
      header.classList.toggle("is-scrolled", !entries[entries.length - 1].isIntersecting);
    }).observe(mark);
  }

  // Меню на телефоне (шапка-плашка, site.css): кнопка в плашке открывает разделы на весь экран, пункты
  // приходят по очереди. Esc и выбор пункта закрывают меню, Tab не уходит за его пределы. Без скрипта
  // на телефоне остаётся строка разделов.
  function buildMenu(header) {
    var wrap = header.querySelector(".wrap"), nav = header.querySelector(".nav");
    if (!wrap || !nav || !window.matchMedia) return;
    var label = EN ? { open: "Menu", close: "Close menu" } : { open: "Меню", close: "Закрыть меню" };
    nav.id = nav.id || "site-nav";
    var btn = document.createElement("button");
    btn.type = "button";
    btn.className = "menu-toggle";
    btn.setAttribute("aria-controls", nav.id);
    btn.setAttribute("aria-expanded", "false");
    btn.setAttribute("aria-label", label.open);
    btn.innerHTML = "<span></span><span></span>";
    wrap.insertBefore(btn, nav);
    var links = [].slice.call(nav.querySelectorAll("a"));
    links.forEach(function (a, k) { a.style.setProperty("--k", String(k)); });
    header.classList.add("has-menu");
    var phone = window.matchMedia("(max-width: 640px)");
    function set(open) {
      header.classList.toggle("is-open", open);
      document.documentElement.classList.toggle("menu-open", open);
      btn.setAttribute("aria-expanded", String(open));
      btn.setAttribute("aria-label", open ? label.close : label.open);
      if (open && links[0]) links[0].focus({ preventScroll: true });
    }
    btn.addEventListener("click", function () { set(!header.classList.contains("is-open")); });
    nav.addEventListener("click", function (e) { if (e.target.closest("a")) set(false); });
    document.addEventListener("keydown", function (e) {
      if (!header.classList.contains("is-open")) return;
      if (e.key === "Escape") { set(false); btn.focus(); return; }
      if (e.key !== "Tab") return;
      var items = [btn].concat(links), i = items.indexOf(document.activeElement);
      if (e.shiftKey && i <= 0) { e.preventDefault(); items[items.length - 1].focus(); }
      else if (!e.shiftKey && i === items.length - 1) { e.preventDefault(); items[0].focus(); }
    });
    var off = function () { if (!phone.matches) set(false); };
    if (phone.addEventListener) phone.addEventListener("change", off); else if (phone.addListener) phone.addListener(off);
  }

  // Пословица на главной и «О студии»: слова проявляются по очереди, когда строка доезжает до нижней
  // трети экрана (site.css, .about blockquote .w). Без IntersectionObserver и при «уменьшить движение»
  // текст с самого начала полным цветом; подпись (cite) не трогаем.
  function words(quote) {
    if (!("IntersectionObserver" in window) || !window.matchMedia ||
        !window.matchMedia("(prefers-reduced-motion: no-preference)").matches) return;
    var spans = [];
    [].slice.call(quote.childNodes).forEach(function (node) {
      if (node.nodeType !== 3 || !node.textContent.trim()) return;
      var frag = document.createDocumentFragment();
      node.textContent.split(/([ \t\n\r]+)/).forEach(function (part) {  // неразрывный пробел не рвём
        if (!part) return;
        if (/^[ \t\n\r]+$/.test(part)) { frag.appendChild(document.createTextNode(" ")); return; }
        var s = document.createElement("span");
        s.className = "w";
        s.textContent = part;
        spans.push(s);
        frag.appendChild(s);
      });
      quote.replaceChild(frag, node);
    });
    var io = new IntersectionObserver(function (entries) {
      // слова одной строки пересекают черту разом — включаем их по порядку чтения, по 60 мс
      var hit = entries.filter(function (e) { return e.isIntersecting; }).map(function (e) { return e.target; });
      hit.sort(function (a, b) { return spans.indexOf(a) - spans.indexOf(b); });
      hit.forEach(function (s, k) {
        s.style.transitionDelay = Math.min(k * 60, 300) + "ms";
        s.classList.add("on");
        io.unobserve(s);
      });
    }, { rootMargin: "0px 0px -30% 0px" });
    spans.forEach(function (s) { io.observe(s); });
  }

  // Появление при прокрутке: карточки ниже первого экрана поднимаются, когда доезжают до него,
  // соседи — с небольшим сдвигом по очереди. То, что видно при загрузке, не трогается, чтобы ничего
  // не мигало; при «уменьшить движение» и без IntersectionObserver всё видно сразу.
  function reveal() {
    if (!("IntersectionObserver" in window) || !window.matchMedia ||
        !window.matchMedia("(prefers-reduced-motion: no-preference)").matches) return;
    var sel = ".section-head, .game, .principle, .news-list li, .promises li, .press-game, .wallpaper, .more-tile, .timeline li, .brand-tile, " +
              ".swatch-card, .specimen, .news-item, .contact, .shots figure, .glance, .doc-body > h2";
    var vh = window.innerHeight, counts = [], parents = [];
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        e.target.classList.add("is-in");
        io.unobserve(e.target);
      });
    }, { rootMargin: "0px 0px -6% 0px" });
    document.querySelectorAll(sel).forEach(function (el) {
      if (el.getBoundingClientRect().top < vh * 0.92) return;  // уже на экране
      var p = el.parentNode, k = parents.indexOf(p);
      if (k < 0) { k = parents.push(p) - 1; counts.push(0); }
      el.classList.add("reveal");
      el.style.setProperty("--d", Math.min(counts[k]++ * 70, 280) + "ms");
      el.addEventListener("transitionend", function done(ev) {
        if (ev.target !== el || !el.classList.contains("is-in")) return;
        el.classList.remove("reveal", "is-in");
        el.style.removeProperty("--d");
        el.removeEventListener("transitionend", done);
      });
      io.observe(el);
    });
  }

  // Петля игры в карточке на главной (data-loop у .game-shot, tools/games.py): беззвучное видео со своего
  // сервера поверх баннера. Грузится и крутится, только пока карточка на экране; при «уменьшить движение»,
  // экономии трафика и без IntersectionObserver остаётся баннер.
  function loops() {
    var shots = document.querySelectorAll(".game-shot[data-loop]");
    if (!shots.length || !("IntersectionObserver" in window) || !window.matchMedia ||
        !window.matchMedia("(prefers-reduced-motion: no-preference)").matches) return;
    var conn = navigator.connection;
    if (conn && conn.saveData) return;
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        var a = e.target, v = a.querySelector("video");
        if (e.isIntersecting) {
          if (!v) {
            var img = a.querySelector("img");
            v = document.createElement("video");
            v.className = "game-loop";
            v.muted = true; v.loop = true; v.playsInline = true;
            v.setAttribute("muted", ""); v.setAttribute("playsinline", ""); v.setAttribute("aria-hidden", "true");
            v.preload = "auto";
            if (img) v.poster = img.currentSrc || img.src;
            v.src = a.getAttribute("data-loop");
            v.addEventListener("playing", function () { a.classList.add("is-playing"); });
            v.addEventListener("error", function () { a.classList.remove("is-playing"); v.remove(); io.unobserve(a); });
            a.appendChild(v);
          }
          var p = v.play();
          if (p && p.catch) p.catch(function () {});
        } else if (v) {
          v.pause();
        }
      });
    }, { threshold: 0.4 });
    shots.forEach(function (a) { io.observe(a); });
  }

  // Ролик на странице игры (.video-link с data-vk-id, tools/games.py): по нажатию на обложку на её месте
  // появляется плеер ВКонтакте. До нажатия страница к ВКонтакте не обращается; без скрипта ссылка
  // открывает ролик в VK Видео в новой вкладке.
  function vkPlayers() {
    document.querySelectorAll(".video-link[data-vk-id]").forEach(function (a) {
      a.addEventListener("click", function (e) {
        if (e.ctrlKey || e.metaKey || e.shiftKey || e.button === 1) return;  // в новой вкладке — как ссылка
        e.preventDefault();
        var f = document.createElement("iframe");
        f.className = "video-frame";
        f.src = "https://vk.com/video_ext.php?oid=" + encodeURIComponent(a.getAttribute("data-vk-oid")) +
                "&id=" + encodeURIComponent(a.getAttribute("data-vk-id")) + "&hd=2&autoplay=1";
        f.title = a.getAttribute("aria-label") || "";
        f.allow = "autoplay; encrypted-media; fullscreen; picture-in-picture; screen-wake-lock";
        f.setAttribute("allowfullscreen", "");
        f.referrerPolicy = "strict-origin-when-cross-origin";
        a.replaceWith(f);
        f.focus();
      });
    });
  }

  function init() {
    var header = document.querySelector(".site-header");
    if (header) { watchHeader(header); buildMenu(header); }
    reveal();
    document.querySelectorAll(".about > blockquote").forEach(words);
    document.querySelectorAll("details.veil").forEach(buildVeil);
    document.querySelectorAll(".shots").forEach(buildZoom);
    loops();
    vkPlayers();
    var hoop = document.getElementById("hoop");
    if (hoop) foldHoop(hoop);
    document.querySelectorAll("[data-hoop]").forEach(buildCanvas);
    document.querySelectorAll("svg.band").forEach(buildBand);
    document.querySelectorAll("[data-copy]").forEach(buildCopy);
    if (document.querySelector("[data-token]")) {
      fillTokens();
      if (window.matchMedia) {
        var mq = window.matchMedia("(prefers-color-scheme: dark)");
        if (mq.addEventListener) mq.addEventListener("change", fillTokens);
      }
    }
    var y = document.querySelector("[data-year]");
    if (y) y.textContent = String(new Date().getFullYear());
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
