#!/usr/bin/env python3
"""IndexNow: сообщает Яндексу адреса из sitemap.xml, чьи страницы изменились с прошлой отправки
(поручение 06). Запускает deploy/seo/apply.sh после каждой выкладки сайта; только стандартная
библиотека Python.

Как понимает, что страница изменилась: хранит sha256 файла каждой страницы из sitemap.xml
в --state. Новый адрес или другой отпечаток — адрес уходит в https://yandex.com/indexnow
(протокол IndexNow: Яндекс делится адресами с другими поисковиками, которые его поддерживают).
Отпечатки сохраняются, только когда Яндекс ответил 200 или 202: не ответил — следующий проход
пришлёт те же адреса ещё раз.

    python3 deploy/seo/indexnow.py --webroot /var/www/gornitsa.games --host gornitsa.games \\
        --key <ключ> --state /var/lib/gornitsa-site/indexnow.json [--dry-run]
"""
import argparse, hashlib, json, pathlib, sys, urllib.error, urllib.request
import xml.etree.ElementTree as ET

ENDPOINT = "https://yandex.com/indexnow"
NS = {"sm": "http://www.sitemaps.org/schemas/sitemap/0.9"}


def page_file(webroot, path):
    """Файл, который nginx отдаст по адресу (try_files $uri $uri.html $uri/)."""
    p = webroot / path.lstrip("/")
    if path.endswith("/"):
        p = p / "index.html"
    for c in (p, p.with_name(p.name + ".html")):
        if c.is_file():
            return c
    return None


def current(webroot, host):
    tree = ET.parse(webroot / "sitemap.xml")
    out = {}
    for loc in tree.getroot().iterfind("sm:url/sm:loc", NS):
        url = (loc.text or "").strip()
        prefix = f"https://{host}"
        if not url.startswith(prefix + "/"):
            continue
        f = page_file(webroot, url[len(prefix):])
        if f:
            out[url] = hashlib.sha256(f.read_bytes()).hexdigest()
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--webroot", type=pathlib.Path, required=True)
    ap.add_argument("--host", required=True)
    ap.add_argument("--key", required=True)
    ap.add_argument("--state", type=pathlib.Path, required=True)
    ap.add_argument("--dry-run", action="store_true", help="только показать, что ушло бы")
    a = ap.parse_args()

    now = current(a.webroot, a.host)
    try:
        sent = json.loads(a.state.read_text(encoding="utf-8")) if a.state.is_file() else {}
    except ValueError:
        sent = {}
    changed = sorted(u for u, h in now.items() if sent.get(u) != h)
    if not changed:
        return 0
    if a.dry_run:
        print("\n".join(changed))
        return 0
    body = json.dumps({"host": a.host, "key": a.key, "keyLocation": f"https://{a.host}/{a.key}.txt",
                       "urlList": changed[:10000]}).encode()
    req = urllib.request.Request(ENDPOINT, data=body, method="POST",
                                 headers={"Content-Type": "application/json; charset=utf-8"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            status = r.status
    except urllib.error.HTTPError as e:
        status = e.code
    except OSError as e:
        print(f"IndexNow: нет связи — {e}", file=sys.stderr)
        return 1
    if status not in (200, 202):
        # 400 — неверный запрос, 403 — ключ не прошёл проверку, 422 — адреса не этого сайта, 429 — часто
        print(f"IndexNow: ответ {status}, адреса не приняты ({len(changed)})", file=sys.stderr)
        return 1
    a.state.parent.mkdir(parents=True, exist_ok=True)
    a.state.write_text(json.dumps(now, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    print(f"IndexNow: отправлено адресов — {len(changed)} (ответ {status})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
