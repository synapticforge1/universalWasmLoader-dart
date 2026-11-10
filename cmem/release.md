# Release — how a release runs, and every release (newest first)

🔒 **One place for every release record (owner, 2026-11-10, workspace D3 / U11).** The design behind
the scripts and the workflow is in [releasing.md](releasing.md); the gate in
[compat-gate.md](compat-gate.md).

## How a release runs (workspace `release-process.md` § 5, the owner's order D1)

"release" is the owner's word, and the level (patch / minor / major) is the owner's too: ask if it
was not given ([working-rules.md](working-rules.md) § Owner commands).

| slot | here |
| --- | --- |
| U1 the go and the level | the owner's; `bump.dart` REQUIRES the level (no default) |
| U2 merge first | CHANGELOG `## Unreleased` (and a README Breaking Changes `\| _next release_ \|` row for a major floor) merged into `main` first; `bump.dart` makes the `bump to vX.Y.Z` commit itself |
| U3 the bump tool | `dart run scripts/bump.dart <level>`: clean tree (untracked count), surface current, the floor from the surface diff, the previous tag's tests for a patch / minor, stamps README / CHANGELOG |
| U4 the release script | `dart run scripts/release.dart [--dry-run]`: on `main`, clean, HEAD = GitHub's `main` + exactly the bump commit, the tag absent here and on GitHub, pub.dev 404, a cold gate (analyze, browser suite, release-script tests, `compat --release`, `pub publish --dry-run`), then ONE push of `main`, read back. No tag, no `tag -f`, no forced push, no publish |
| U5 `checks` | on every push of `main` (`contents: read`): the gate; "is this a release?" (`ci_release.dart state`: `new` / `rerun` / `none`); for a release `compat --release` on the untagged candidate + the publish dry run |
| U6 `tag` | CI's annotated `vX.Y.Z` on the pushed commit (REST `git/tags` + `git/refs`, `contents: write`); there already = done, elsewhere = refused; read back |
| U7 `release` | the GitHub Release page FROM the tag (H32's order), the pub.dev link on top, BEFORE the publish |
| U8 `publish` | pub.dev last (`contents: read`, the credentials secret): skip if pub.dev serves the version, else `dart pub publish --force`; credentials removed; **read-back fatal** (pub.dev must serve the version) |
| U9 pins | 0 `uses:`; Dart SDK by version + sha256 in every job; top-level `permissions: {}`; `concurrency` per ref, never cancelled |
| U10 as a user | after the run, by hand: a scratch package that depends on `universal_wasm_loader: X.Y.Z` resolves it from pub.dev and analyzes clean |
| U11 the record | this file, § Release History |
| U12 failure | "Re-run failed jobs": the tag job finds its tag, the page job its page, the publish job skips the upload; never a new tag for the same code, never a moved tag |

**Not filled yet, with the reason:**

- **U8 credential: still the `PUB_DEV_CREDENTIALS` secret, not pub.dev's OIDC automated publishing**
  (the § 6 target). Reasoned, not measured (2026-11-10): pub.dev's automated publishing accepts a
  token only from a run whose ref matches the tag pattern configured on pub.dev (`v{{version}}`).
  Under D1 this run starts from a push of `main` (`refs/heads/main`). A tag made with
  `GITHUB_TOKEN` starts no run, though a `workflow_dispatch` on the tag ref can, and pub.dev has a
  setting to accept dispatch events. So OIDC needs (1) the owner to enable automated publishing on
  the package's pub.dev admin page, with the dispatch option, and (2) the publish moved into a
  dispatched run on the tag. The old premise "the reusable workflow is forbidden" is no obstacle:
  the OIDC token can be minted with plain `run:` steps. 🗓️ OWNER decision.
- **U10 in CI:** done by hand after the run, not in the workflow. It installs and analyzes package
  code, which the publish job must not run (C30).

## Release History

- **0.3.2 (2026-11-09), tag → `e22927c`.** *Changed:* no library change. The release workflow got
  its third job, `release`, the only one with `contents: write`; `publish` got a read-only token. The
  release script got a time limit on every call, a second tag check after the POST, the pub.dev link
  in the notes, and 15 committed tests. README describes the three jobs. *Checked:* `bump.dart
  patch` (floor patch, v0.3.1's 37 tests green). Run 42656931575: `checks` 16:39:12–16:41:03Z;
  `publish` 16:41:06–16:41:32Z, upload 16:41:29Z; `release` 16:41:34–16:42:00Z. Page `v0.3.2` by
  `github-actions[bot]`, `published_at` 16:41:58Z, not a draft, `releases/latest`; tag unmoved. A
  release's `created_at` is its commit's date: order it by `published_at`.
- **0.3.1 (2026-11-09), tag → `08e24c4`.** *Changed:* no library change. The GitHub Release is made
  through the REST API instead of the GitHub CLI (H30), and a re-run skips the pub.dev upload when
  the version is there (C34). README describes the release workflow. *Checked:* floor patch, v0.3.0's
  37 tests green. Run 42633779743 green; pub.dev 0.3.1 at 14:22:27Z; page `v0.3.1` read back.
- **0.3.0 (2026-11-07), tag → `1fe255f`.** *Changed:* **SPEC 4.0.0** (`5e24ae3`), a breaking pre-1.0
  minor: only an absent `.wit` gives raw exports; strict `.wit` parsing; every WIT import needs a
  callback, and its result is checked; typed calls check count and kinds; `s64` as `BigInt`;
  `LoadOptions` (30 s fetch limit, `LoadCancelToken`). README row 0.3.0. *Checked:* floor major,
  v0.2.1's 9 tests green; 37 tests. Run 42436175882 green (the first two-job run). pub.dev 0.3.0.
- **0.2.1 (2026-10-22), tag → `ae231db`.** *Changed:* no library change: the README §10 correction,
  the stamped H7 fixtures, the Breaking Changes table. *Checked:* the first release through the
  compatibility gate (floor patch, previous-tag tests 9/9); run 39803257031 green; pub.dev at 15:17Z.
- **0.2.0 (2026-10-22), tag → `5f1c294`.** *Changed:* SPEC §10 (`6579312`): the WASI-P1 shim and
  `_initialize`; no API change. *Checked:* run 39797726044 green, the browser tests ran on the
  runner; pub.dev at 14:41Z. The first release after the org transfer.
- **0.1.0 (2026-06-24), tag → `4376a8a`.** *Changed:* the first publish (SPEC 3.0.0, web backend).
  The archive is 12 KB after `.pubignore`; `jrmarcum` is the pub.dev uploader (no verified
  publisher).
