#!/usr/bin/env python3
"""backup-github — копия всех репозиториев студии с GitHub на компьютер владельца (docs/backup.md,
«Копия GitHub»). Раз в неделю по расписанию: на случай, если пропадёт доступ к GitHub или всё
придётся разворачивать заново. Нужны Python 3.8+, git и GitHub CLI (`gh`): один раз `gh auth login`
тем аккаунтом, которому видны все репозитории, и `gh auth setup-git` — чтобы git брал вход у gh
(ключей на серверах студии для этого не нужно). Ходит только в REST API GitHub.

  python3 backup-github.py <папка>                 все репозитории Nefeste
  python3 backup-github.py <папка> --assets 0      без файлов релизов (APK)

Что кладёт в <папка>:
  git/<репо>.git           зеркало (git clone --mirror): все ветки, теги, история; обновляется
  bundles/ГГГГ-ММ-ДД/      <репо>.bundle — один файл на репозиторий (git bundle --all), проверен
                           `git bundle verify`; хранятся 4 последних — их удобно унести на флешку
  github/<репо>/           Issues и PR с комментариями, ревью, релизы, метки, вехи, переменные
                           Actions (значения — они не секретны), имена секретов Actions (значений
                           GitHub не отдаёт никому), ключи развёртывания (открытые)
  releases/<репо>/<тег>/   файлы релизов (APK и др.) последних 3 релизов каждого репозитория

Восстановить репозиторий: `git clone <папка>/bundles/<дата>/<репо>.bundle <репо>` или
`git clone --mirror <папка>/git/<репо>.git` и `git push --mirror <новый адрес>` (docs/restore.md).
"""
import argparse
import datetime as dt
import json
import os
import shutil
import subprocess
import sys

OWNER = "Nefeste"
KEEP_BUNDLES = 4


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def gh_api(path):
    """GET с разбором страниц сами: `--paginate` у старых gh склеивает массивы без разделителя."""
    out, page = [], 1
    while True:
        sep = "&" if "?" in path else "?"
        p = run(["gh", "api", f"{path}{sep}per_page=100&page={page}"])
        if p.returncode != 0:
            raise RuntimeError(p.stderr.strip() or p.stdout.strip())
        data = json.loads(p.stdout or "null")
        if isinstance(data, dict):
            if "total_count" not in data:   # просто объект (сам репозиторий)
                return data
            # список в обёртке: {"total_count":…, "secrets":[…]} или {"variables":[…]}
            items = next((v for k, v in data.items() if k != "total_count" and isinstance(v, list)), [])
            out.extend(items)
            if len(items) < 100:
                return out
        elif isinstance(data, list):
            out.extend(data)
            if len(data) < 100:
                return out
        else:
            return out
        page += 1


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    os.replace(tmp, path)


def mirror(repo, root):
    path = os.path.join(root, "git", repo + ".git")
    if os.path.isdir(path):
        p = run(["git", "-C", path, "remote", "update", "--prune"])
    else:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        p = run(["git", "clone", "--mirror", "-q", f"https://github.com/{OWNER}/{repo}.git", path])
    if p.returncode != 0:
        raise RuntimeError(p.stderr.strip())
    # пустой репозиторий: веток нет — bundle не из чего делать
    refs = run(["git", "-C", path, "for-each-ref", "--count=1"]).stdout.strip()
    return path, bool(refs)


def bundle(repo, path, day_dir):
    os.makedirs(day_dir, exist_ok=True)
    out = os.path.join(day_dir, repo + ".bundle")
    p = run(["git", "-C", path, "bundle", "create", out, "--all"])
    if p.returncode != 0:
        raise RuntimeError(p.stderr.strip())
    v = run(["git", "bundle", "verify", out], cwd=path)
    if v.returncode != 0:
        raise RuntimeError("bundle verify: " + v.stderr.strip())
    return os.path.getsize(out)


def metadata(repo, root):
    d = os.path.join(root, "github", repo)
    r = f"repos/{OWNER}/{repo}"
    saved = {}
    parts = {
        "repo.json": r,
        "issues.json": f"{r}/issues?state=all",                 # Issues и PR (у PR есть поле pull_request)
        "issue-comments.json": f"{r}/issues/comments",
        "pulls.json": f"{r}/pulls?state=all",
        "pull-review-comments.json": f"{r}/pulls/comments",
        "releases.json": f"{r}/releases",
        "labels.json": f"{r}/labels",
        "milestones.json": f"{r}/milestones?state=all",
        "actions-variables.json": f"{r}/actions/variables",
        "actions-secret-names.json": f"{r}/actions/secrets",   # только имена и даты
        "deploy-keys.json": f"{r}/keys",
    }
    for name, path in parts.items():
        try:
            data = gh_api(path)
        except RuntimeError as e:
            data = {"error": str(e)[:300]}   # нет прав на раздел (например, на секреты) — не беда
        write_json(os.path.join(d, name), data)
        if isinstance(data, list):
            saved[name] = len(data)
    return saved


def assets(repo, root, keep):
    if keep == 0:
        return 0
    try:
        rels = gh_api(f"repos/{OWNER}/{repo}/releases")
    except RuntimeError:
        return 0
    got = 0
    for rel in rels[:keep] if keep > 0 else rels:
        tag = rel.get("tag_name")
        if not tag or not rel.get("assets"):
            continue
        d = os.path.join(root, "releases", repo, tag)
        if os.path.isdir(d) and len(os.listdir(d)) >= len(rel["assets"]):
            continue
        os.makedirs(d, exist_ok=True)
        p = run(["gh", "release", "download", tag, "-R", f"{OWNER}/{repo}", "-D", d, "--skip-existing"])
        if p.returncode == 0:
            got += 1
    return got


def prune_bundles(root):
    base = os.path.join(root, "bundles")
    if not os.path.isdir(base):
        return
    days = sorted(x for x in os.listdir(base) if len(x) == 10 and x[4] == "-")
    for old in days[:-KEEP_BUNDLES]:
        shutil.rmtree(os.path.join(base, old), ignore_errors=True)


def main():
    ap = argparse.ArgumentParser(description="Копия репозиториев студии с GitHub")
    ap.add_argument("root", help="папка для копий (на диске с шифрованием)")
    ap.add_argument("--assets", type=int, default=3,
                    help="файлы скольких последних релизов каждого репозитория скачивать (0 — не скачивать, -1 — всех)")
    a = ap.parse_args()
    for tool in ("git", "gh"):
        if shutil.which(tool) is None:
            sys.exit(f"Не найдена программа {tool} — см. docs/backup.md, «Копия GitHub»")
    if run(["gh", "auth", "status"]).returncode != 0:
        sys.exit("gh не вошёл в GitHub: выполните gh auth login")

    try:   # закрытые видны только владельцу, поэтому список — «мои репозитории», а не профиль Nefeste
        listed = gh_api("user/repos?affiliation=owner&visibility=all")
    except RuntimeError as e:
        sys.exit("Не получил список репозиториев: " + str(e))
    repos = sorted(({"name": x["name"], "isPrivate": x["private"], "isArchived": x["archived"]}
                    for x in listed if x["owner"]["login"].lower() == OWNER.lower()), key=lambda x: x["name"])
    day_dir = os.path.join(a.root, "bundles", dt.date.today().isoformat())
    report, ok = {"date": dt.datetime.now().astimezone().isoformat(timespec="seconds"), "repos": {}}, True
    for repo in repos:
        name = repo["name"]
        entry = {"private": repo["isPrivate"], "archived": repo["isArchived"]}
        try:
            path, has_refs = mirror(name, a.root)
            entry["bundle_bytes"] = bundle(name, path, day_dir) if has_refs else 0
            entry["github"] = metadata(name, a.root)
            entry["release_downloads"] = assets(name, a.root, a.assets)
            print(f"{name}: ок ({entry['bundle_bytes'] // 1024} КБ, issues и PR: {entry['github'].get('issues.json', 0)})")
        except RuntimeError as e:
            entry["error"] = str(e)[:300]
            ok = False
            print(f"{name}: ОШИБКА — {entry['error']}")
        report["repos"][name] = entry
    write_json(os.path.join(a.root, "last-run.json"), report)
    prune_bundles(a.root)
    print(f"Репозиториев: {len(repos)}. " + ("Всё сохранено." if ok else "ЕСТЬ ОШИБКИ — см. выше и last-run.json"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
