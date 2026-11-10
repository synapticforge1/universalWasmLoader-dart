# Releasing — the design behind bump, release and the CI order

**Version source:** `pubspec.yaml` `version:` is the single source of truth, and it ARMS a release:
a push of `main` whose version has no tag yet IS a release (CI tags and publishes it). **Nothing is
pushed, tagged or published unless the owner says so**; a published version can never be deleted.
How a release runs, slot by slot, and every release: [release.md](release.md).

## The flow (🔒 the owner's order D1, 2026-11-10, workspace H33)

1. **Notes first (U2):** CHANGELOG `## Unreleased` (and, when the floor is major, a README Breaking
   Changes `| _next release_ |` row), merged into `main`. pub.dev's validator warns when CHANGELOG
   does not mention the version, and `release.dart`'s gate stops on that warning (rehearsed).
2. `dart run scripts/bump.dart <patch|minor|major>`. The level is REQUIRED. It refuses a dirty tree
   (untracked files count), then runs the compatibility gate ([compat-gate.md](compat-gate.md)):
   floor, previous-tag tests, surface current. It rewrites the `version:` line, stamps the README
   row and the CHANGELOG heading, and commits `bump to vX.Y.Z` with only those files.
3. `dart run scripts/release.dart [--dry-run]`: the U4 guards, a cold gate, then ONE push of
   `main`, read back. It never tags and never publishes.
4. CI (`.github/workflows/publish.yml`, on that push): `checks` → `tag` → `release` → `publish`.

## `publish.yml` — `run:`-only, four jobs, in the owner's order

Built under the pre-transfer policy, which permitted only `jrmarcum`-owned actions: ANY third-party
`uses:` step caused a `startup_failure`. So every step is a plain `run:`; nothing needs `uses:`.

**Each job holds only what it needs** (C30, owner 2026-11-07: "I agree with splitting into two jobs
if it will maintain better privacy"; H32, 2026-11-09: the page from its own job; D1, 2026-11-10: the
order). The rules: no third-party package code runs in a job that sees the pub.dev credentials, the
job that sees them has no write token, and only `tag` / `release` can write.

- **Trigger:** `push` of `main`. Top-level `permissions: {}`. `concurrency` per ref, never
  cancelled. **Dart SDK 3.13.7** from dart-archive's zip, pinned by version AND sha256
  (`eb99aed2…e867229`, the published sum, re-hashed from the 238,850,892-byte download on
  2026-11-10) in every job, instead of apt's moving `stable`.
- **`checks`** (`contents: read`, no secret): a full tokenless clone checked out at `github.sha`
  (history and tags for the gate) → Dart → **"is this a release?"** (`ci_release.dart state`, with
  the read-only token) → `pub get` → `analyze` → fixture check → **browser tests, BLOCKING** (they
  were best-effort before 2026-11-10) → release-script tests → gate self-test → for a release,
  **`compat.dart --release`** (the untagged candidate) and `dart pub publish --dry-run`. For an
  ordinary push, the compat report only warns.
- **`tag`** (`needs: checks`, only for a release; `contents: write`; no checkout): Dart, then
  `ci_release.dart` fetched ALONE from `raw.githubusercontent.com/<repo>/<github.sha>/…`, then `tag`.
- **`release`** (`needs: [checks, tag]`; `contents: write`; no checkout): the script alone again,
  then `github-release`: the page from the tag, BEFORE the publish.
- **`dispatch`** (`needs: [checks, release]`; `actions: write` only; no checkout): Dart, then
  `ci_release.dart` and `pubspec.yaml` fetched alone at `github.sha` → `dispatch
  publish-pubdev.yml` (the tag must exist; `POST actions/workflows/…/dispatches` with `ref` = the
  tag, 204) → **`pub-readback`, fatal** (40 × 15 s).
- **`publish-pubdev.yml`** (separate workflow, `workflow_dispatch` only; one job, `contents: read`
  + `id-token: write`, no secret): the ref must be `refs/tags/v*`; a tokenless clone at
  `github.sha` → Dart → **`verify-released`** (the tag peels to this commit AND its page was made
  by `github-actions[bot]`, or refuse) → `pub-has`: skip, or mint pub.dev's OIDC token (GitHub's
  OIDC endpoint, audience `https://pub.dev`, masked; `dart pub token add https://pub.dev --env-var
  PUB_TOKEN`) and `dart pub publish --force` (downloads the deps to validate; pub has no install
  scripts, so none of their code runs) → `pub-readback`. **Until 2026-11-10 the publish job used
  the `PUB_DEV_CREDENTIALS` secret** (written with `umask 077`, removed after); no workflow reads it
  any more.

A tag made with the job's `GITHUB_TOKEN` starts no workflow run, so tag, page and publish follow
`needs:` in the SAME run. That is why the trigger is `main`, not a tag.

**Before 2026-11-10:**

- The trigger was a `v*` tag that `release.dart` pushed (with `git tag -f` and a forced tag push).
- The page came after the upload.
- The browser tests did not block.
- Dart came from apt.

Before 2026-11-07 it was ONE job that ran the checks and then wrote the credentials on the same
runner.

## `scripts/compat.dart --release` — the untagged candidate (2026-11-10)

Under D1, `checks` runs BEFORE the tag exists:

- **Normal case:** `v<version>` is absent, and the previous release is the newest tag below HEAD.
- **Re-run:** CI has already tagged HEAD, so the previous release is the newest tag below HEAD^.
- **A `v<version>` tag on ANOTHER commit:** refused with "a published tag never moves".

Rehearsed in all three states. The third first CRASHED (`bumpKind 0.3.3 → 0.3.3`, exit 255), because
`git describe` from HEAD found the misplaced tag itself as "previous". It now refuses cleanly before
computing anything (exit 1).

## `scripts/ci_release.dart` — the network steps (H30, C34, H32, H33)

It imports only `dart:` libraries and runs from `$RUNNER_TEMP`, OUTSIDE the package, or is fetched
alone. So `dart run` resolves nothing and loads no dependency (the C30 rule). **Every network call
has ONE time limit, connect to last byte** (30 s; `CI_HTTP_TIMEOUT_MS` overrides it for the tests).
The run's ref is `main`, so every command takes the tag from **`RELEASE_TAG`** (set by `checks`),
not from `GITHUB_REF_NAME`. Commands:

- **`state <pubspec>`**: `kind=new` (the tag is not on GitHub), `rerun` (on this commit) or `none`
  (on another commit: an ordinary push), plus `release=`, `tag=`, `version=`, appended to
  `$GITHUB_OUTPUT`.
- **`tag [--dry-run]`**: absent → `POST git/tags` (annotated, message = the tag, object =
  `GITHUB_SHA`) then `POST git/refs`. A 422 on the ref is decided by the read-back. On this commit
  already = done; on another commit = refused. The read-back must peel to `GITHUB_SHA`.
- **`github-release [--dry-run]`**:
  1. The tag exists and peels to `GITHUB_SHA` (`POST /releases` would otherwise CREATE a missing
     tag, loader-rs's hazard).
  2. An existing page is done.
  3. `POST` with `generate_release_notes` and the pub.dev link on top, read back (not a draft), and
     the tag peeled again.
- **`pub-has <pubspec>`**: 0 = pub.dev serves the version (skip), 3 = not yet, 1 = cannot tell or
  `RELEASE_TAG` ≠ `v<version>`. **Why:** pub.dev never takes a version twice. Before this, a failure
  after the upload made every re-run stop at "version exists" (measured: the H19 tag re-runs,
  2026-10-26).
- **`pub-readback <pubspec>`**: polls (`READBACK_TRIES` 20 × `READBACK_WAIT_MS` 15 s) until pub.dev
  serves `version` = the pubspec's; otherwise exit 1. A green upload is not proof.

**Tests, committed: `test/ci_release_test.dart`** (`@TestOn('vm')`, **30 cases**, ~25 s). Each case
runs the script as a child process against an in-process mock of GitHub and pub.dev that logs every
request. The cases:

- `state`: new (GITHUB_OUTPUT written), rerun (annotated), none.
- `tag`: create, done, elsewhere refused, 422, 500, read-back elsewhere, dry-run, and no
  `RELEASE_TAG` / no token (no request at all).
- `github-release`: the 11 H32 cases, a stalled API among them.
- `pub-has`: 4 cases. `pub-readback`: at once, after two 404s, never, and another version.

**Inverted 2026-11-10** by eight one-line mutants, each caught by its own case(s): tag without
read-back, a moved tag accepted, rerun ≡ none, readback without the version check, no sha check, no
existing-page stop, no post-POST check, no time limit. ⚠️ **On Windows, a child process with an EMPTY
environment cannot open sockets** (Winsock needs `SystemRoot`), so the test passes the parent
environment minus the variables the script reads.

**Why Dart and not a Bun step** (workspace rule 9 suggests Bun; rule 1 allows the repo's own
language): every job already has the Dart SDK. A Bun download would put a second runtime beside the
credentials, with a pin that rule 10 / H31 would make this repo move at every Bun upgrade.

## Rehearsed 2026-11-10 (D1), GitHub untouched

The setup: a scratch bare repo as `origin` and a scratch clone of this repo. Then:

- **`bump.dart`:** no level, a junk level and an untracked file were each refused, with nothing
  changed. A real patch made ONE commit, `bump to v0.3.3`.
- **`release.dart`** refused each of these with nothing pushed:
  - another branch;
  - an untracked file;
  - a commit on top of the bump;
  - the tag local;
  - the tag on the remote.
- **The cold gate:** the dry run stopped at `pub publish --dry-run` because CHANGELOG had no 0.3.3
  notes (U2 enforced). With the notes merged first, the real run pushed `main` = the bump commit,
  read it back, and **no tag existed anywhere** afterwards.
- **Against the real GitHub, read-only:**
  - `state`: `v0.3.2` at its commit → `rerun`; at a later commit → `none`; 9.9.9 → `new`.
  - `tag --dry-run`: at its commit → done; elsewhere → refused; v9.9.9 → would create.

**MEASURED on GitHub, the non-release path (2026-11-10, owner: "push"):** the push of `e4b85a0` ran
**42877135280**:

- `checks` green, so the pinned Dart SDK installed, the BLOCKING browser tests passed on the runner,
  and `state` answered "not a release";
- `tag` / `release` / `publish` skipped, because 0.3.2 is already tagged on `e22927c`.

**MEASURED on GitHub by 0.3.3 (2026-11-10)** — every item below, including pub.dev's OIDC token
from a run dispatched on the tag (after the owner's pub.dev "Update"; [release.md](release.md)).
Still unexercised: the pub-has skip inside a real re-run of the publish run. The list, as it stood
before 0.3.3:

- the CI-made tag;
- `needs:` chaining from a push of `main`;
- the dispatch of `publish-pubdev.yml` on the tag, and pub.dev accepting its OIDC token;
- the read-back.

## Owner setup (one-time) and the credential

**Since 2026-11-10: pub.dev automated publishing (OIDC)**, enabled by the owner on the package's admin
page: repository `synapticforge1/universalWasmLoader-dart`, tag pattern `v{{version}}`, push and
workflow_dispatch events, no environment. No credential is stored. The owner was told why a stored
token is the larger risk: `PUB_DEV_CREDENTIALS` held the owner's personal `dart pub login` refresh
token, long-lived, valid for every package the account can upload. **Retire it after the first OIDC
release succeeds:** delete the repo secret, and revoke the login (🗓️ owner;
[release.md](release.md)). Before that date the secret held that token; it survived the org
transfer.

## Scripting runtime 🔒 (owner, 2026-10-22)

Scripts here are **Dart only** (`dart run scripts/...`); releasing needs only the Dart SDK. Bun is
the workspace's TypeScript runner; a TypeScript script, if ever unavoidable, runs under `bun`.
**No Bun version is pinned or named anywhere in this repo** (measured 2026-11-09: `git grep -i bun`
outside `cmem/` → 0), so workspace rule 10 / H31 has nothing to move here. The bash twins
`bump.sh` / `release.sh` were deleted in `3883d61` (no shell scripts, workspace rule).

## Release history

Moved to [release.md](release.md) § "Release History" (2026-11-10, workspace U11).
