# The compatibility gate (workspace letter H6, built 2026-10-22)

🔒 Binding (owner, 2026-09-20; workspace `../../cmem/layout-and-packaging.md` § "The compatibility
gate"): "backward compatible" is a gate result, never a judgment made at bump time. Ported from
`-js`'s `cmem/compat-gate.md` design into Dart.

## What runs where

| Rule | File | Runs in |
| --- | --- | --- |
| 1, the SURFACE | `scripts/surface.dart` → `api-surface.json` (committed) | `dart run scripts/surface.dart` writes it; staleness checked by every gate run |
| 2, the FLOOR | `scripts/compat.dart` `floorOf` | `bump.dart` (refuses below it), `compat.dart` (report), `compat.dart --release` on the tag (CI, blocking) |
| 3, BEHAVIOUR | `compat.dart` `previousTests` | same places; required green for a patch or minor |
| 4, deprecate first | README `### ⚠️ Breaking Changes` | gate requires a `\| _next release_ \|` row when the floor is major; `bump.dart` stamps the version into it |
| 5, re-baseline alone | the stale-snapshot refusal | an intended surface change is its own commit, with the reason |
| 6, pre-1.0 | `problemsFor` | 0.y.z: a minor is allowed where the floor says major; the row is still mandatory |
| self-test | `scripts/check_compat_gate.dart` (31 checks) | CI, blocking; no git/Chrome/network |

**The surface:** the `SPEC.md` version declared once in README (`` `SPEC.md` **vX.Y.Z** ``), plus every
name each public library in `lib/` (not `lib/src/`) exports. It is read through `package:analyzer`
(14.6, `exportNamespace.definedNames2`): one key per symbol and one per public member (constructors
as `.new`, setters as `name=`), valued by the analyzer's `displayString()`. Members get a `static `
prefix, top-level functions do not. An element kind it cannot key THROWS. 34 keys on 2026-10-22.

**The floor:** removed or changed → major; added → minor; nothing → patch; the SPEC version moves it
by its own level (lowered → major). ⚠️ It errs high, on purpose. A changed DEFAULT value and a
renamed constructor POSITIONAL parameter both count as "changed", because `displayString` includes
them. If that becomes a burden, add reviewed exceptions, not a looser rule.

**Previous-tag tests:** a `git worktree` of the tag in the system temp dir; its `lib/` replaced by
the current `lib/`, its `pubspec.yaml` by the current one; its `test/` (test file AND fixtures)
untouched; `dart pub get`; `dart test -p chrome --reporter expanded`. Counts are read from the
OUTPUT, and green needs exit 0, at least one pass and no failures. On RED the last 15 lines of
output are printed. The worktree is always removed.

**Consumers (Rule 3, second half):** no known pub.dev package depends on this one; nothing to run.

## Inverted end to end, 2026-10-22 (a scratch clone; nothing in the repo was broken)

| Mutant | Command | Result |
| --- | --- | --- |
| bool result decode inverted in `abi.dart` (surface unchanged) | `bump patch` | refused: floor patch, previous-tag tests RED 8 pass / 1 fail (`booleans_50`) |
| `kebabToCamel` dropped from the barrel, NOT re-baselined | `bump patch` | refused: snapshot STALE, floor major ("symbol removed"), no Breaking row |
| same, re-baselined | `bump patch` | refused: below the floor (major), no row |
| same | `bump minor` | refused: 0.x exemption applied, still no row |
| same + `\| _next release_ \|` row | `bump minor` | ALLOWED → 0.3.0; README row and CHANGELOG heading stamped |
| tagged v0.3.0 with that change | `compat --release` | passes (0.x minor at a major floor, row present) |
| tagged v0.2.1 with the same change | `compat --release` | BLOCKED: patch below the floor (major) |
| `loaderName()` added and exported, re-baselined | `bump patch` | refused: floor minor ("symbol added") |

The previous-tag tests stayed green for the removal: no test calls `kebabToCamel`, which is correct.

**First real use (2026-10-22, 0.2.1):** `bump.dart patch` was allowed at floor patch, with the
previous-tag tests 9/9. In CI, the self-test and `compat --release` passed on the runner (run
39803257031), so the CI half has now run for real, not only in the scratch clone.

## Traps met building it

- `copyDir` first joined a separator-terminated base path wrongly (`lib` + `src\abi.dart` →
  `libsrc\abi.dart`), leaving `lib/` empty. The suite then reported "RED, 0 pass 1 fail", a harness
  fault that looked like a loader fault. Reproducing by hand (9/9) exposed it. It now copies through
  URIs and throws if it copies nothing. (best-practices L1)
- `hasBreakingRow` first searched from inside the heading line itself, so the next-heading cut
  happened at offset 0 and it never found a row. Only the self-test's must-ALLOW case caught it.
  (best-practices L2)
- Child Dart processes are launched with `Platform.resolvedExecutable`, so they run on the same SDK
  as the script. This was chosen as a precaution; whether `dart` from PATH would also work under
  scoop Flutter was NOT measured.
