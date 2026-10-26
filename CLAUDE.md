# universalWasmLoader-dart — pointer

> **Project memory lives in `cmem/`. Start at [`cmem/INDEX.md`](cmem/INDEX.md)**; the status is in
> [`cmem/open-work.md`](cmem/open-work.md). This file is only a pointer and holds no authoritative
> knowledge.

> **At session start, read `../../cmem/handoffs.md` for letters addressed to this repo.** The workspace
> session (`../../cmem/INDEX.md`) reviews across the sibling repos and reports there; nothing is ever
> written into this repo from outside. (owner directive, 2026-09-20)

The Dart port of the Universal WASM Loader: `universal_wasm_loader` on pub.dev, web backend
(`dart:js_interop`), implementing `-js`'s `SPEC.md` 3.0.0 including §10. GitHub:
**https://github.com/synapticforge1/universalWasmLoader-dart**.

The **"update the project memory"** and **"look for code issues"** triggers are defined in
`cmem/INDEX.md` and are binding.

## What bites in the first five minutes

- **Nothing is pushed, tagged or published unless the owner says so.** A `v*` tag publishes to
  pub.dev irreversibly. Bump with `dart run scripts/bump.dart`: it runs the compatibility gate and
  refuses a bump below the floor (`cmem/compat-gate.md`).
- **Tests are browser-only:** `dart test -p chrome` (plain `dart test` runs nothing useful).
- **Scripts are Dart; no shell scripts, no Python, no heredocs; `git commit -F <file>`.** LF
  everywhere (`.gitattributes`).
- **No personal information in any committed file** — no drive or user-profile path; use
  `<repo-root>` or a relative path (the path test: `cmem/working-rules.md` § Privacy). Git's
  `safe.directory` for the workspace folder is in the machine's system config (2026-10-26).
