"""QR-код коротких ссылок сайта — без сторонних библиотек (сайт собирается и на сервере).

Нужен одному: человек открыл страницу игры на компьютере, а игра ставится на телефон из RuStore.
Код ведёт на gornitsa.games/go/<игра> — тот же переход, что и кнопка (tools/seo.py).

Только то, что нужно сайту: байтовый режим, уровень исправления ошибок M, версии 1–3 (до 42 байт,
один блок Рида — Соломона). Стандарт — ISO/IEC 18004; проверка — tools/check.py сверяет код
с образцом, а образец прочитан сканером (docs/journal/2026-11.md, 13.11).
"""

# версия: (кодовых слов данных, кодовых слов исправления ошибок) — уровень M
VERSIONS = {1: (16, 10), 2: (28, 16), 3: (44, 26)}


def _rs(data, n):
    """Остаток от деления на порождающий многочлен степени n над GF(256), x^8+x^4+x^3+x^2+1."""
    def mul(a, b):
        r = 0
        for i in range(7, -1, -1):
            r = ((r << 1) ^ ((r >> 7) * 0x11D)) & 0xFF
            if (b >> i) & 1:
                r ^= a
        return r
    gen, root = [0] * (n - 1) + [1], 1
    for _ in range(n):
        for j in range(n):
            gen[j] = mul(gen[j], root)
            if j + 1 < n:
                gen[j] ^= gen[j + 1]
        root = mul(root, 2)
    rem = [0] * n
    for b in data:
        f = b ^ rem.pop(0)
        rem.append(0)
        rem = [r ^ mul(g, f) for r, g in zip(rem, gen)]
    return rem


def _codewords(text):
    raw = text.encode("utf-8")
    ver = next((v for v, (cap, _) in VERSIONS.items() if len(raw) + 2 <= cap), None)
    if ver is None:
        raise ValueError(f"QR: «{text}» длиннее 42 байт — версии 1–3 не хватит")
    cap, ecc = VERSIONS[ver]
    bits = [0, 1, 0, 0] + [(len(raw) >> i) & 1 for i in range(7, -1, -1)]
    for b in raw:
        bits += [(b >> i) & 1 for i in range(7, -1, -1)]
    bits += [0] * min(4, cap * 8 - len(bits))
    bits += [0] * (-len(bits) % 8)
    data = [int("".join(map(str, bits[i:i + 8])), 2) for i in range(0, len(bits), 8)]
    pad = (0xEC, 0x11)
    data += [pad[i % 2] for i in range(cap - len(data))]
    return ver, data + _rs(data, ecc)


MASKS = [lambda x, y: (x + y) % 2 == 0, lambda x, y: y % 2 == 0, lambda x, y: x % 3 == 0,
         lambda x, y: (x + y) % 3 == 0, lambda x, y: (x // 3 + y // 2) % 2 == 0,
         lambda x, y: x * y % 2 + x * y % 3 == 0, lambda x, y: (x * y % 2 + x * y % 3) % 2 == 0,
         lambda x, y: ((x + y) % 2 + x * y % 3) % 2 == 0]


def _penalty(m):
    """Правила выбора маски 1, 2 и 4 стандарта (длинные полосы, квадраты 2 × 2, перекос тёмного)."""
    n, score = len(m), 0
    for lines in (m, list(zip(*m))):
        for line in lines:
            run = 1
            for a, b in zip(line, line[1:]):
                run = run + 1 if a == b else 1
                score += 3 if run == 5 else (1 if run > 5 else 0)
    for y in range(n - 1):
        for x in range(n - 1):
            if m[y][x] == m[y][x + 1] == m[y + 1][x] == m[y + 1][x + 1]:
                score += 3
    dark = sum(map(sum, m))
    return score + 10 * (abs(dark * 20 - n * n * 10) // (n * n))


def matrix(text):
    """Модули кода: список строк из 0 и 1 (1 — тёмный)."""
    ver, words = _codewords(text)
    n = 17 + 4 * ver
    m = [[0] * n for _ in range(n)]
    fn = [[False] * n for _ in range(n)]

    def put(x, y, dark):
        m[y][x], fn[y][x] = int(bool(dark)), True

    for i in range(n):  # линии синхронизации
        put(6, i, i % 2 == 0)
        put(i, 6, i % 2 == 0)
    for cx, cy in ((3, 3), (n - 4, 3), (3, n - 4)):  # поисковые узоры с полем
        for dy in range(-4, 5):
            for dx in range(-4, 5):
                x, y = cx + dx, cy + dy
                if 0 <= x < n and 0 <= y < n:
                    put(x, y, max(abs(dx), abs(dy)) not in (2, 4))
    if ver > 1:  # выравнивающий узор
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                put(n - 7 + dx, n - 7 + dy, max(abs(dx), abs(dy)) != 1)

    def fmt(mask):
        data = mask  # уровень M — биты 00
        rem = data
        for _ in range(10):
            rem = (rem << 1) ^ ((rem >> 9) * 0x537)
        bits = ((data << 10) | rem) ^ 0x5412
        bit = lambda i: (bits >> i) & 1
        for i in range(6):
            put(8, i, bit(i))
        put(8, 7, bit(6)); put(8, 8, bit(7)); put(7, 8, bit(8))
        for i in range(9, 15):
            put(14 - i, 8, bit(i))
        for i in range(8):
            put(n - 1 - i, 8, bit(i))
        for i in range(8, 15):
            put(8, n - 15 + i, bit(i))
        put(8, n - 8, 1)

    fmt(0)  # место под служебные биты — до раскладки данных
    bits = [(w >> i) & 1 for w in words for i in range(7, -1, -1)]
    i, right = 0, n - 1
    while right >= 1:
        if right == 6:
            right = 5
        for vert in range(n):
            for j in range(2):
                x = right - j
                y = n - 1 - vert if ((right + 1) & 2) == 0 else vert
                if not fn[y][x] and i < len(bits):
                    m[y][x] = bits[i]
                    i += 1
        right -= 2

    best = None
    for k, mask in enumerate(MASKS):
        fmt(k)
        cand = [[m[y][x] ^ (not fn[y][x] and mask(x, y)) for x in range(n)] for y in range(n)]
        p = _penalty(cand)
        if best is None or p < best[0]:
            best = (p, cand)
    return best[1]


def svg(text, label, quiet=4):
    """Код картинкой SVG: тёмные модули одной фигурой, поле в четыре модуля. Цвета задаёт site.css (.qr)."""
    m = matrix(text)
    n = len(m) + 2 * quiet
    path = "".join(f"M{x + quiet} {y + quiet}h1v1h-1z" for y, row in enumerate(m) for x, v in enumerate(row) if v)
    return (f'<svg class="qr-code" viewBox="0 0 {n} {n}" width="{n * 4}" height="{n * 4}" role="img" '
            f'aria-label="{label}" shape-rendering="crispEdges"><rect width="{n}" height="{n}" fill="#fff"/>'
            f'<path fill="#000" d="{path}"/></svg>')
