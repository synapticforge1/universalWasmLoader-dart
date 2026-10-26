# Working rules — the checklist (rules, not lessons; lessons are in best-practices.md)

The workspace floor is `../../cmem/working-rules.md`; these are what bite in this repo.

## Git and release

- **Nothing is pushed, tagged or published unless the owner says so.** A `v*` tag publishes to
  pub.dev irreversibly ([releasing.md](releasing.md)).
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
