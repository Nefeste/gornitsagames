This repository is the site of the «Горница» studio, https://gornitsa.games: static pages in Russian
and English built by `build.py` from `src/`, plus the install scripts of the studio's machine
(`deploy/`). It has no `package.json`. Merging into `main` is publishing the site.

## Studio charter — read first

This project belongs to the «Горница» studio. Studio-wide rules live only in the public
charter repository `Nefeste/gornitsa` (https://github.com/Nefeste/gornitsa); this repository
keeps only what is specific to the project. Before changing anything — and after a context
reset — read the charter's `AGENTS.md`, then `docs/05-rules.md` (hard rules for every game)
and `docs/04-process.md` (how work is done). Raw files:
`https://raw.githubusercontent.com/Nefeste/gornitsa/main/<path>`.

Current state of this project: `STATUS.md` (it is not repeated here).

Precedence: the owner's recorded decision → the charter → this project's documents. A project
rule may narrow a charter rule, never weaken it. If a document here restates or contradicts
the charter, replace it with a link or report the contradiction to the owner.

## Read before changing anything

- `README.md` (Russian) — structure, how to change text, news, search, the machine, game
  pages built from `store/site/` of the games; `docs/backup.md`, `docs/restore.md`,
  `docs/devlog.md`; the journal is `docs/journal/YYYY-MM.md`.
- This repository is **public** (studio ADR 0017): never put secrets, personal data, private
  repository details or unapproved drafts into a commit, PR or Issue.
- **All PRs are merged by the owner** (`.github/CODEOWNERS` is `*`): a merge publishes the site.
  Never merge, never label `ревью: ок`, never enable auto-merge.
- News with `review: draft` is not shown on the site; only a human sets `review: checked`.

## Commands

```bash
python3 build.py            # build the site from src/ into site/
python3 tools/check.py      # site checks (also run by CI on every PR, site.yml)
```
