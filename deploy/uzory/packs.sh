#!/usr/bin/env bash
# uzory-packs (таймер uzory-packs.timer, каждые 5 минут; ставит deploy/uzory/setup.sh): новые картинки
# «Узоров» по сети — https://gornitsa.games/uzory/v1/ (docs/05-process.md, «Выкладывание наборов», и
# docs/03-server-api.md в репозитории Nefeste/uzory). CI «Узоров» (content.yml) кладёт в открытую ветку
# packs все выложенные наборы, подписанный каталог и скрипт свёртки счётчиков — одним коммитом без
# истории, как ветку vps веб-версии. Входа на эту машину у CI нет: ветку забирает этот скрипт.
#
#   1. ветка packs → /var/lib/uzory-packs/repo; тот же коммит, что в прошлый раз, — делать нечего;
#   2. подпись каталога (v1/catalog.sig — Ed25519 точных байтов v1/catalog.json, base64) — одним из
#      открытых ключей /etc/uzory/catalog.pub (по строке; ключи — из src/state/keys.ts «Узоров»);
#      не сошлась — ничего не трогается;
#   3. каждый набор каталога есть в ветке, его размер и SHA-256 — как в каталоге; уже выложенный набор
#      с другими байтами — ошибка: выложенное не меняется никогда;
#   4. в /srv/gornitsa/uzory/v1/ — сначала новые наборы (выложенные не переписываются), потом подпись,
#      потом каталог: телефон никогда не увидит каталог со ссылкой на ещё не выложенный набор;
#   5. stats/fold.ts → /srv/gornitsa/uzory/stats/ — свёртка счётчиков (таймер uzory-stats).
#
# Отдаёт /uzory/v1/ nginx сайта (uzory-nginx). Откат — прежний каталог с его подписью: CI кладёт его в
# ветку снова (наборы не удаляются никогда). Пути для проверки на своей машине — переменными UZORY_PACKS_*.

set -euo pipefail

REPO="${UZORY_PACKS_REPO:-https://github.com/Nefeste/uzory.git}"
STATE="${UZORY_PACKS_STATE:-/var/lib/uzory-packs}"
DEST="${UZORY_PACKS_DEST:-/srv/gornitsa/uzory}"
KEYS="${UZORY_CATALOG_KEYS:-/etc/uzory/catalog.pub}"

install -d -m 755 "$STATE" "$DEST/v1/packs" "$DEST/stats"
if [[ ! -d "$STATE/repo/.git" ]]; then
  rm -rf "$STATE/repo"
  git init -q "$STATE/repo"
  git -C "$STATE/repo" remote add origin "$REPO"
fi
if ! git -C "$STATE/repo" fetch -q --depth 1 origin packs 2>/dev/null; then
  if git ls-remote --exit-code --heads "$REPO" packs >/dev/null 2>&1; then
    echo "uzory-packs: не удалось забрать ветку packs из $REPO" >&2
    exit 1
  fi
  exit 0   # ветки ещё нет: первый каталог не выложен
fi
HEAD="$(git -C "$STATE/repo" rev-parse FETCH_HEAD)"
if [[ "$(cat "$STATE/applied" 2>/dev/null || true)" == "$HEAD" ]]; then
  exit 0
fi
git -C "$STATE/repo" checkout -q --force --detach FETCH_HEAD

python3 -I - "$STATE/repo" "$DEST" "$KEYS" <<'PY'
import base64, hashlib, json, os, subprocess, sys, tempfile

src, dest, keys_file = sys.argv[1:4]
v1 = os.path.join(src, "v1")


def fail(msg):
    print(f"uzory-packs: {msg} — ничего не тронуто", file=sys.stderr)
    sys.exit(1)


def read(path):
    with open(path, "rb") as f:
        return f.read()


catalog = read(os.path.join(v1, "catalog.json"))
sig_text = read(os.path.join(v1, "catalog.sig"))
try:
    sig = base64.b64decode(sig_text.strip(), validate=True)
except ValueError:
    fail("подпись каталога — не base64")
keys = [l.strip() for l in read(keys_file).decode().splitlines() if l.strip() and not l.startswith("#")]

# Ed25519 — openssl: открытый ключ — 32 байта base64, к ним — заголовок SubjectPublicKeyInfo
SPKI = bytes.fromhex("302a300506032b6570032100")
ok = False
with tempfile.TemporaryDirectory() as t:
    with open(os.path.join(t, "sig"), "wb") as f:
        f.write(sig)
    with open(os.path.join(t, "msg"), "wb") as f:
        f.write(catalog)
    for k in keys:
        raw = base64.b64decode(k)
        if len(raw) != 32:
            fail(f"ключ «{k}» в {keys_file} — не 32 байта")
        with open(os.path.join(t, "pub.der"), "wb") as f:
            f.write(SPKI + raw)
        r = subprocess.run(["openssl", "pkeyutl", "-verify", "-pubin", "-keyform", "DER", "-inkey", os.path.join(t, "pub.der"),
                            "-rawin", "-in", os.path.join(t, "msg"), "-sigfile", os.path.join(t, "sig")], capture_output=True)
        if r.returncode == 0:
            ok = True
            break
if not ok:
    fail("подпись каталога не сошлась ни с одним ключом")

data = json.loads(catalog)
new = []
for p in data.get("packs", []):
    rel = p["file"]
    if not rel.startswith("packs/") or "/" in rel[len("packs/"):] or ".." in rel:
        fail(f"странный путь набора «{rel}»")
    body = read(os.path.join(v1, rel)) if os.path.exists(os.path.join(v1, rel)) else None
    if body is None:
        fail(f"набора {rel} нет в ветке")
    if len(body) != p["bytes"] or hashlib.sha256(body).hexdigest() != p["sha256"]:
        fail(f"набор {rel} не сходится с каталогом (размер или SHA-256)")
    there = os.path.join(dest, "v1", rel)
    if os.path.exists(there):
        if hashlib.sha256(read(there)).hexdigest() != p["sha256"]:
            fail(f"набор {rel} уже выложен с другими байтами")
    else:
        new.append((rel, body))


def put(path, body):
    """Атомарно: временный файл рядом и переименование — nginx не отдаст половину файла."""
    d = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".uzory-")
    with os.fdopen(fd, "wb") as f:
        f.write(body)
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)


for rel, body in new:
    put(os.path.join(dest, "v1", rel), body)
put(os.path.join(dest, "v1", "catalog.sig"), sig_text)
put(os.path.join(dest, "v1", "catalog.json"), catalog)
fold = os.path.join(src, "stats", "fold.ts")
if os.path.exists(fold):
    put(os.path.join(dest, "stats", "fold.ts"), read(fold))
print(f"uzory-packs: каталог выложен — наборов {len(data.get('packs', []))}, новых {len(new)}")
PY

echo "$HEAD" > "$STATE/applied"
