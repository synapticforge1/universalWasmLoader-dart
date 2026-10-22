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
green (0.2.0); third-party `uses:` steps have not been tried there and nothing needs them. Steps:
full `git clone --branch <tag>` (history and tags: the gate needs the previous tag) → Dart from the
official apt repo → `pub get` → `analyze` → **fixture check (blocking)** → best-effort
`dart test -p chrome` (warns, does not block) → **gate self-test (blocking)** → **`compat.dart
--release` (blocking)** → write `PUB_DEV_CREDENTIALS` to `pub-credentials.json` (all candidate
paths) → `dart pub publish --force` → `gh release create`.

**Why a credentials file, not OIDC:** pub.dev's automated publishing is a third-party reusable
workflow, which the policy forbade. **Owner setup (one-time, done):** `dart pub login` locally,
then copy the full `pub-credentials.json` into the repo secret `PUB_DEV_CREDENTIALS`; rotate by
logging in again. The secret contains a refresh token and survived the org transfer.

## Scripting runtime 🔒 (owner, 2026-10-22)

Scripts here are **Dart only** (`dart run scripts/...`); releasing needs only the Dart SDK. Bun is
the workspace's TypeScript runner; a TypeScript script, if ever unavoidable, runs under `bun`. The
bash twins `bump.sh` / `release.sh` were deleted in `a75b167` (no shell scripts, workspace rule).

## Release history (summaries; git is the archive)

- **0.2.0 (2026-10-22), tag → `f550a37`.** SPEC §10 (`985039f`); no API change. The first real run of
  `release.dart`, and the first release after the org transfer. CI run 39797726044 was green on every
  step, the browser tests really ran on the runner, and it published at 14:41Z.
- **0.1.0 (2026-06-24), tag → `edd1e46`.** First publish, through CI (then `release.sh`); the archive
  is 12 KB after `.pubignore`. `jrmarcum` is the pub.dev uploader; there is no verified publisher.
- ⚠️ The `ubuntu-latest` label moves to Ubuntu 26 from 2026-10-19. If a future run breaks, check the
  apt Dart install first.
