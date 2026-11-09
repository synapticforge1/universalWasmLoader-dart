# Releasing — bump, gate, tag, CI publish

**Version source:** `pubspec.yaml` `version:` is the single source of truth. **Nothing is tagged or
pushed unless the owner says so**; a pushed `v*` tag publishes to pub.dev, and a published version
can never be deleted.

## The flow

1. `dart run scripts/bump.dart [patch|minor|major]` (default `patch`). It runs the compatibility
   gate first ([compat-gate.md](compat-gate.md)) and refuses a bump below the floor, or a
   patch/minor with the previous tag's tests red. On success it rewrites the `version:` line only,
   stamps README's `| _next release_ |` Breaking Changes row and CHANGELOG's `## Unreleased` heading
   with the new version, and changes nothing if refused.
2. `dart run scripts/release.dart` — commits the pending bump (`pubspec.yaml`, `README.md`,
   `CHANGELOG.md`), tags `vX.Y.Z`, pushes `main` and the tag. Runs from any cwd. It NEVER runs
   `dart pub publish` locally (mirrors `-js`'s `scripts/publish.ts`).
3. The tag triggers `.github/workflows/publish.yml`.

Write the CHANGELOG `## Unreleased` entry (and a Breaking Changes row when the floor is major)
BEFORE bumping. Pre-flight worth running: `dart analyze`, `dart format`, `dart test -p chrome`,
`dart pub publish --dry-run` (its only acceptable warning is the uncommitted bump).

## `publish.yml` — `run:`-only

Built under the pre-transfer policy, which permitted only `jrmarcum`-owned actions: ANY third-party
`uses:` step (`actions/checkout`, `dart-lang/setup-dart`, the pub.dev OIDC reusable workflow) caused
a `startup_failure`. So every step is a plain `run:`. Under `synapticforge1` this workflow has run
green (0.2.0); third-party `uses:` steps have not been tried there and nothing needs them.

**Two jobs since 2026-11-07 (workspace C30; owner: "I agree with splitting into two jobs if it will
maintain better privacy").** The rule: no third-party package code runs in a job that sees the
pub.dev credentials.
- **`checks`** (`contents: read`, no secret): full `git clone --branch <tag>` WITHOUT a token (the
  repo is public, so no token lands in `.git/config`; history and tags, because the gate needs the
  previous tag), asserted to equal `github.sha` → Dart from the official apt repo → `pub get` →
  `analyze` → **fixture check (blocking)** → best-effort `dart test -p chrome` (warns, does not
  block) → **gate self-test (blocking)** → **`compat.dart --release` (blocking)**.
- **`publish`** (`needs: checks`; `contents: write`, used only by the GitHub Release POST): a
  fresh runner, shallow tokenless clone asserted to equal `github.sha` (so a moved tag cannot
  publish untested code) → Dart SDK → copy `scripts/ci_release.dart` to `$RUNNER_TEMP` → write
  `PUB_DEV_CREDENTIALS` (`umask 077`, all candidate paths) → **publish, unless pub.dev already has
  the version** (`ci_release.dart pub-has`; else `dart pub publish --force`, which downloads the
  deps to validate; pub has no install scripts, so none of their code runs) → remove the
  credentials (`if: always()`) → **GitHub Release through the REST API** (`ci_release.dart
  github-release`, with `GITHUB_TOKEN`).

**`scripts/ci_release.dart` (2026-11-09; workspace H30, C34).** It imports only `dart:` libraries
and runs from `$RUNNER_TEMP`, OUTSIDE the package, so `dart run` resolves nothing and loads no
dependency (the C30 rule). There are two commands:
- **`pub-has <pubspec>`**: exit 0 if pub.dev answers 200 for the version (the upload is
  skipped), 3 on 404 (publish it), and 1 otherwise. It also returns 1 when `GITHUB_REF_NAME` ≠
  `v<version>`. **Why:** pub.dev never takes a version twice. Before this, a failure AFTER the
  upload (in the Release step) made every re-run stop at "version exists" and skip the Release.
  That was measured: the H19 tag re-runs, 2026-10-26.
- **`github-release [--dry-run]`**: the tag must exist on GitHub and peel to `GITHUB_SHA`
  (annotated tags are followed). `POST /releases` would otherwise CREATE a missing tag from the
  default branch (loader-rs's hazard, workspace rule 9). An existing release is done (exit 0), so
  a re-run is safe. A POST must answer 201, and the release is then read back (`tag_name`, not a
  draft).

**Why Dart and not a Bun step** (workspace rule 9 suggests Bun; rule 1 allows the repo's own
language): the publish job already has the Dart SDK. A Bun download would put a second runtime
beside the credentials, with a sha256 pin that rule 10 / H31 would make this repo move at every
Bun upgrade. **Measured 2026-11-09, outside the package:** against the real services with
`--dry-run`, `v0.3.0` at its own commit → tag verified, release exists, exit 0; `v0.3.0` at
another commit → refused, 1; `v9.9.9` → "does not exist", 1. `pub-has`: 0.3.0 → 0; tag `v0.2.1`
with pubspec 0.3.0 → 1; 9.9.9 → 3. Against a mock GitHub (`GITHUB_API_URL`): create → one POST
(`Bearer`, `generate_release_notes`), then a read-back; a re-run sends no POST; an annotated tag is
peeled; a 422 POST → 1; `--dry-run` sends no POST; no token → refused before any request. The
step's exit-code idiom was checked under `bash -e` (0 → skip, 3 → publish, 1 → fail). **MEASURED
on GitHub with 0.3.1** (run 42633779743, attempt 1): `pub-has` said "publish", the upload
succeeded, and `github-release` created Release `v0.3.1` (by `github-actions[bot]`, not a draft,
notes `v0.3.0...v0.3.1`). The tag stayed `08e24c4`. **Not exercised:** the skip path on a real
re-run, because nothing failed.

Before 2026-11-07 it was ONE job that ran all the checks and then wrote the credentials on the same
runner, so a process left behind by a dependency could have read them (reasoned, never observed).

**Why a credentials file, not OIDC:** pub.dev's automated publishing is a third-party reusable
workflow, which the policy forbade. **Owner setup (one-time, done):** `dart pub login` locally,
then copy the full `pub-credentials.json` into the repo secret `PUB_DEV_CREDENTIALS`; rotate by
logging in again. The secret contains a refresh token and survived the org transfer.

## Scripting runtime 🔒 (owner, 2026-10-22)

Scripts here are **Dart only** (`dart run scripts/...`); releasing needs only the Dart SDK. Bun is
the workspace's TypeScript runner; a TypeScript script, if ever unavoidable, runs under `bun`.
**No Bun version is pinned or named anywhere in this repo** (measured 2026-11-09: `git grep -i bun`
outside `cmem/` → 0), so workspace rule 10 / H31 has nothing to move here; if Bun is ever added,
its notations follow the latest installed Bun. The
bash twins `bump.sh` / `release.sh` were deleted in `3883d61` (no shell scripts, workspace rule).

## Release history (summaries; git is the archive)

- **0.3.1 (2026-11-09, owner: "release"), tag → `08e24c4`.** No library change. It carries the
  README's Releasing text, and it was the first real run of `ci_release.dart` (H30 / C34).
  `bump.dart patch`: floor patch, v0.3.0's 37 tests green on the current code. Run 42633779743 was
  green in both jobs. pub.dev read back: latest 0.3.1, published 14:22:27Z. GitHub Release `v0.3.1`
  was read back through the REST API.

- **0.3.0 (2026-11-07), tag → `1fe255f`.** SPEC 4.0.0 (`5e24ae3`), a breaking pre-1.0 minor
  ([compat-gate.md](compat-gate.md) Rule 6, README row 0.3.0). The first run of the two-job
  workflow: run 42436175882, `checks` green (gate blocking steps included), then `publish` green
  (credentials written, published, removed, GitHub release created). The browser-test step is
  best-effort and its log was not read (the logs need a signed-in download), so whether Chrome ran
  on the runner is unconfirmed; locally 37/37. pub.dev read back: latest 0.3.0.

- **0.2.1 (2026-10-22), tag → `ae231db`.** No library change: the README §10 correction, the stamped
  H7 fixtures, the Breaking Changes table. It is the first release through the compatibility gate:
  locally, `bump.dart patch` was allowed at floor patch with the previous-tag tests 9/9. In CI, run
  39803257031 passed every step, including the three blocking ones (fixtures, gate self-test,
  `compat --release`). For a patch, that last step can only pass if the previous tag's suite ran
  green in Chrome on the runner. Published at 15:17Z, and pub.dev's README now shows the corrected
  §10 text.

- **0.2.0 (2026-10-22), tag → `5f1c294`.** SPEC §10 (`6579312`); no API change. The first real run of
  `release.dart`, and the first release after the org transfer. CI run 39797726044 was green on every
  step, the browser tests really ran on the runner, and it published at 14:41Z.
- **0.1.0 (2026-06-24), tag → `4376a8a`.** First publish, through CI (then `release.sh`); the archive
  is 12 KB after `.pubignore`. `jrmarcum` is the pub.dev uploader; there is no verified publisher.
- ⚠️ The `ubuntu-latest` label moves to Ubuntu 26 from 2026-10-19. If a future run breaks, check the
  apt Dart install first.
