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

## Line endings 🔒 (owner, 2026-10-22, `b9f4e9c`)

`.gitattributes`: `* text=auto eol=lf` + `*.wasm binary`. That gives LF in the index and in every
working tree, whatever a machine's `core.autocrlf` is (this machine: system `true`, global
`input`). Verify with `git ls-files --eol`: every text file is `i/lf w/lf`. Never fix line endings
with `git config`.

## Memory

- `cmem/` is the single home of project memory; [INDEX.md](INDEX.md) has one line per file. The
  status line lives only in [open-work.md](open-work.md).
- Never run a formatter on `cmem/`. Absolute dates; every number carries its date.
- At session start, read `../../cmem/handoffs.md` for letters addressed to this repo.
