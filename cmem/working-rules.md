# Working rules — the checklist (rules, not lessons; lessons are in best-practices.md)

The workspace floor is `../../cmem/working-rules.md`; these are what bite in this repo.

## Git and release

- **Nothing is pushed, tagged or published unless the owner says so.** ⚠️ **The `pubspec.yaml`
  version line ARMS a release:** a push of `main` whose version has no tag yet IS one. CI checks,
  tags, makes the page and publishes to pub.dev, irreversibly (the owner's order D1, 2026-11-10;
  [release.md](release.md)). So a version change lands only through `bump.dart` + `release.dart`,
  never inside other work, and no tag is ever made by hand: CI makes it.
- 🔒 **No third-party package code runs in a CI job that holds the pub.dev credentials** (owner,
  2026-11-07, workspace C30). Checks that execute dependencies (`analyze`, `dart test`, `dart run
  scripts/...`) belong in `checks`, which has no secret. `publish` runs only the SDK's `dart pub
  publish` and `scripts/ci_release.dart` (`dart:` imports only, run from outside the package), with
  a READ-only token. Only `release` has `contents: write`, and it has no secret and no checkout. A
  new check goes into `checks`, never into `publish` or `release` ([releasing.md](releasing.md)).
- 🔒 **Every tagged release gets its GitHub Release page from CI** (owner, 2026-11-09, workspace
  H32): from the `release` job, never by hand and never with the CLI; only NEW tags get pages (no
  backfill).
- 🔒 **No GitHub CLI, locally or in CI** (owner, 2026-11-08; workspace rule 9, letter H30): check
  GitHub with `git ls-remote origin` or a registry's or GitHub's public REST API. CI reaches GitHub
  through `scripts/ci_release.dart` with `GITHUB_TOKEN`. A task only the web UI can do (a Release
  page by hand, a topic, a Support request) is an OWNER item, never "blocked on the CLI". A
  release-workflow change lands BEFORE a release and is proven by the next real run.
- **Bun versions** (owner, 2026-11-09; workspace rule 10, letter H31): every Bun notation is the
  latest installed Bun. This repo names none today ([releasing.md](releasing.md) § Scripting runtime).
- Commit messages go through a file: `git commit -F <file>`. Never a heredoc.
- An intended API change re-baselines `api-surface.json` in its OWN commit, stating the reason,
  before the bump commit ([compat-gate.md](compat-gate.md)).
- Nothing is written into a sibling repo from here (workspace rule 8.1). Read `-js` freely; copy its
  fixtures INTO this repo only as [testing.md](testing.md) describes.

## Tooling hard rules (workspace, 🔒)

- **Scripts are Dart** (`scripts/*.dart`). No shell scripts, no Python, no heredocs for any content.
  A TypeScript script, if ever unavoidable, runs under `bun`.
- File content goes through the editor tools or a Dart/.NET write that is byte-exact; PowerShell 5.1
  `Set-Content -Encoding utf8` writes a BOM.
- When the exit code is the measurement, do not pipe it.

## Line endings 🔒 (owner, 2026-10-22, `18a2559`)

`.gitattributes`: `* text=auto eol=lf` + `*.wasm binary`. That gives LF in the index and in every
working tree, whatever a machine's `core.autocrlf` is (this machine: system `true`, global
`input`). Verify with `git ls-files --eol`: every text file is `i/lf w/lf`. Never fix line endings
with `git config`.

## Privacy 🔒 (owner, 2026-10-22 / 2026-10-23 / 2026-10-26; workspace letters H18, H22)

- **No secrets and no personal information in any committed file, commit message, package or
  issue.** The workspace text is `../../cmem/working-rules.md` § Records.
- **The path test is "is it machine-specific?", not "is it absolute?"** NOT public: any path that
  records the owner's machine layout (a user profile, the project tree on a drive, other drives,
  scoop / AppData installs, scratchpad or session ids). Fine: repo- or sibling-relative paths,
  env vars, placeholders (`<repo-root>`), and a CONVENTION path that names nothing about one
  machine (`%APPDATA%\dart\pub-credentials.json` in the README is one). A scan hit is a CANDIDATE
  judged by this test; do not scrub convention paths.
- **The one email exception:** the maintainer contact address in the manifest field a registry
  reads, as the git commit author / committer address, and in ONE committed `cmem/` contact note
  (owner, 2026-10-26, H28). Nowhere else; not repeated. This repo keeps it on commits only
  (`pubspec.yaml` has no email field; there is no contact note).
- Private facts go in the gitignored `cmem/local/` (machine notes; any private backup).
- **Scan before committing, binaries included** (`-a`: a compiler's debug output embeds the build
  machine's paths): `git grep -n -a -i -E '[A-Za-z]:[\\/]+(Programs|Users|scoop|tools)[\\/]'`.
  The history was purged of the one leak (`CLAUDE.md`) on 2026-10-26
  ([history-map-2026-10-26.md](history-map-2026-10-26.md)).

## Memory

- `cmem/` is the single home of project memory; [INDEX.md](INDEX.md) has one line per file. The
  status line lives only in [open-work.md](open-work.md).
- Never run a formatter on `cmem/`. Absolute dates; every number carries its date.
- At session start, read `../../cmem/workspace-correspondence.md` (rows addressed to this repo, and
  rows touching the work at hand) and then the letter it points to in `../../cmem/handoffs.md`.
- **A sibling's commit id is looked up in its history map before it is quoted** (workspace H21);
  this repo's own map is [history-map-2026-10-26.md](history-map-2026-10-26.md).

## Owner commands: "commit", "push", "release" (owner, 2026-11-10)

🔒 Written into every project by the workspace session on the owner's direction (2026-11-10:
"please write that into each project"; workspace `cmem/working-rules.md` Tooling rule 12, letter
H34). When the owner says:

- **"commit"** — first run "update the project memory files" (re-derive this repo's `cmem/` from
  its current state), then commit to the branch being worked on. Nothing is pushed.
- **"push"** — perform "commit", then merge the branch into `main`, then push `main` (and the
  working branch) to GitHub (`origin`) and read it back with `git ls-remote`.
- **"release"** — perform "push", then the release process: the workspace's
  `cmem/release-process.md` §§ 5–8 — CI checks first, then CI pushes the tag, then the GitHub
  Release page from the tag, then the publish to the registry — recorded in `cmem/release.md`
  § "Release History" (newest first, a summary of what changed). The level (patch / minor /
  major) is the owner's: ask if it was not given.

Each command includes the one before it, and none goes further than its own word (a "commit"
never pushes, a "push" never releases). This repo's own gate and merge rules apply at each step.
