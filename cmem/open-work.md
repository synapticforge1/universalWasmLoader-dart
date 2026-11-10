# Open work — the ONE list (status lives here and nowhere else)

**State (2026-11-10):** **0.3.3 is the latest on pub.dev: SPEC 4.0.0** + §10 (workspace C29),
tag `v0.3.3` → `f59a239`, its library 0.3.0's (released 2026-11-07, `1fe255f`). Releases run in the
owner's order: `release.dart` pushes `main` only, and CI checks → tags → makes the page → publishes
to pub.dev with **OIDC, no stored secret** ([release.md](release.md); measured end to end by 0.3.3).
⚠️ A push of `main` with an untagged `pubspec.yaml` version IS a release. Every release passes the
blocking compatibility gate in CI, and no job that can write or publish runs package code (C30). The
history was purged of a drive path and force-pushed on 2026-10-26 (H19,
[history-map-2026-10-26.md](history-map-2026-10-26.md)).

## Open

- **🗓️ OWNER: retire the pub.dev secret, now that OIDC is proven (0.3.3, 2026-11-10).** Delete the
  repo secret `PUB_DEV_CREDENTIALS` (Settings → Secrets and variables → Actions; no workflow reads it
  since 2026-11-10), and revoke the `dart pub login` it came from (the Google account's third-party
  access for the Dart / pub client). And consider turning OFF "push events" in pub.dev's automated
  publishing: nothing uses them, and a future workflow listening to tag pushes could otherwise
  publish a hand-pushed tag that skipped the checks. Why the secret was the larger risk:
  [releasing.md](releasing.md) § Owner setup.
- **pub.dev documentation score: read back 20/20 once pub.dev has analyzed 0.3.3** (owner,
  2026-11-10). It was 10/20: 10/10 dartdoc coverage (40 of 45, 88.9 %), 0/10 "Package has an
  example". 0.3.3 adds `example/main.dart` and the five missing constructor docs. When read on
  2026-11-10 at 19:14Z, the metrics API still showed 0.3.2's report (not yet analyzed).
- **🗓️ OWNER: send the GitHub Support cleanup request (H19's last step).** GitHub still serves the
  19 pre-purge commits by hash until its own GC. Measured 2026-10-26: public repo, 0 forks, 0 pull
  requests, so no other ref holds them. Send from the account that administers the org, at
  support.github.com → "Remove data from a repository" (sensitive data removal). The letter, ready
  to paste:

  > **Subject:** Sensitive data removal — synapticforge1/universalWasmLoader-dart
  >
  > Hello. I administer the organization `synapticforge1`. The public repository
  > `synapticforge1/universalWasmLoader-dart` had a local filesystem path of my development machine
  > committed in `CLAUDE.md`. I have rewritten the repository's history to remove it and
  > force-pushed every branch and tag on 2026-10-26 (`main` is now `0bcd2e9`; tags `v0.1.0`,
  > `v0.2.0`, `v0.2.1` moved). The repository has no forks and no pull requests.
  >
  > The old commits are still reachable by hash. Please remove the cached views of these
  > dereferenced commits and run garbage collection on the repository:
  >
  > `c7884df40f035dd7436f346b1fd4d9d91f3c0c9f`, `e75c046114925726b201d7e3f09a0c20e58602da`,
  > `6aa6fb00428705d4460ea9b47eaa36d8ad7ba2f3`, `b62fdeb17040d480d9ae55d6c69b6e501018c00e`,
  > `edd1e46fe97bb409357a8b72e9532bb06c4da23c`, `2429345dce607c932688076e5f791e5eb6b8dc8e`,
  > `985039ff17aa09de74436c9df3c37feee9e029d0`, `4a9b9b746f1a6669eb693b5345d48f5574853d61`,
  > `df673dcebf348d2cea0d82fb6477997e6f4faf89`, `99edd4090a88ac01463faa5f987dbf98ea7be1d8`,
  > `a75b167429ef3995ec8bed59a43d2dc988e1fd33`, `e5529e490ba5324ab11208233d441e682f27cb50`,
  > `f550a3772929c63803f172367ba3f4be1af3233c`, `b9f4e9ceb3c8926f12281d1afec538f4a7165de4`,
  > `11dacb970fd6d1093e37d450d0485aa0700519b6`, `bc53669f37fdb48ebd448c59a041e15fbc533e25`,
  > `36378fdecf66445ce54d39c2ec756c50b3c29373`, `1fc075753797023db6efe5200ccd0f7c7357980b`,
  > `256c699cd1a2036f6c9cbdcef6906499e4d332f6`
  >
  > The sensitive content is the file `CLAUDE.md` in each of them. Thank you.

  Close this item when Support confirms; then `https://github.com/synapticforge1/universalWasmLoader-dart/commit/256c699`
  should return 404 (that is the check).
- **S5:** check the two §10 tests against the shared §10 conformance test, once the workspace
  defines one ([testing.md](testing.md)).
- **Native backend** (`dart:ffi` → wasmtime C API): tracked future ([overview.md](overview.md)).

## Done (summaries with pointers)

- **H33 / H34, 2026-11-10** (owner: "review workspace for items needing this project's attention
  and make the requested fixes"). **H34:** the workspace's "Owner commands" section committed as
  found (`0c9b1f9`). **H33:** converged to `release-process.md` § 5 in the owner's order D1
  (`fe28a40` + the follow-up commits) — details per slot in [release.md](release.md), design and
  evidence in [releasing.md](releasing.md):
  - `bump.dart`: the level required, clean tree, makes the bump commit;
  - `release.dart` rewritten: guards, a cold gate, pushes `main` only, never tags;
  - `compat --release` on the untagged candidate; its tag-elsewhere crash fixed;
  - `ci_release.dart`: `state`, `tag`, `pub-readback`; tests 15 → 30, eight mutants;
  - `publish.yml`: on `main`, `checks` → `tag` → `release` → `publish`; Dart pinned by sha256;
    browser tests blocking; `permissions: {}`; `concurrency`;
  - `cmem/release.md` created (U11), the history moved there.

  The card's "U5 browser tests non-blocking", "U9 Dart from apt", "U8 no read-back", "U4 `tag -f`,
  two pushes, no clean-tree guard" and "U3 no clean-tree check" are closed. U8's OIDC is an owner
  item (above).

- **0.3.2 released (2026-11-09, owner: "update the projects memory files, commit, push then
  release"), tag → `e22927c`;** no library change. The first run of the three-job workflow (H32),
  run 42656931575, attempt 1, green in every job. Measured:
  - pub.dev: 0.3.2, uploaded 16:41:29Z;
  - Release `v0.3.2`: `author.login` = `github-actions[bot]`, published 16:41:58Z in the
    `release` job (16:41:34–16:42:00Z), after `publish` (16:41:06–16:41:32Z); not a draft;
    `releases/latest`; the pub.dev link on top of the generated notes;
  - the tag is unmoved.

  ⚠️ A release's `created_at` is its COMMIT's date (16:39:45Z here), not the page's: read
  `published_at` to order it against the upload.

- **H32 (the Release page from CI), 2026-11-09** (owner: "review workspace for items needing this
  project's attention and make the requested fixes"). This repo was NOT on the change list (loader-py's
  survey: 5 tags / 5 pages / 5 by `github-actions[bot]`), but it ran the recipe's order without its
  shape. Brought to the recipe ([releasing.md](releasing.md)):
  - a separate `release` job: `contents: write` only, no secret, no checkout; `publish` is now
    read-only;
  - one time limit per network call, connect to last byte (only the headers were limited);
  - the tag re-checked after the POST, and the pub.dev link on top of the notes;
  - committed mock tests (`test/ci_release_test.dart`, 15 cases, blocking in `checks`), inverted by
    5 mutants.
  First page so far: `v0.3.1`, `author.login` = `github-actions[bot]` (the old layout). Rule
  recorded in [working-rules.md](working-rules.md).

- **0.3.1 released (2026-11-09, owner: "release"), tag → `08e24c4`;** no library change. It was the
  first real run of `scripts/ci_release.dart`: run 42633779743 green; pub.dev 0.3.1; GitHub Release
  `v0.3.1` created through the REST API and read back ([releasing.md](releasing.md)). The re-run
  skip path stays unexercised (nothing failed).

- **Workspace letters, 2026-11-09** (owner: "review workspace for items needing this project's
  attention and make the requested fixes"). **H30 (no GitHub CLI, CI included):** `publish.yml`'s
  last CLI call (`gh release create`, the letter's `publish.yml:166`) is replaced by
  `scripts/ci_release.dart github-release`. The rule is recorded in
  [working-rules.md](working-rules.md); the design, the choice of Dart over Bun, and the
  measurements are in [releasing.md](releasing.md). **C34 (record-only, finding (1)'s analogue
  here, fixed):** the publish step skips the upload when pub.dev already has the version
  (`ci_release.dart pub-has`), so a re-run after a failed Release step completes. Findings (2)–(4)
  do not apply: no npm, no setup-deno, no workflow test that reads YAML. **H31 (Bun, record-only):**
  this repo names no Bun version; the rule is recorded. **C31** closed as its creator (the
  workspace verified it 2026-11-08). Commits `a3fd3c1` + `5b31d52`, **pushed 2026-11-09** (owner:
  "update the project memory files, commit then push"), with this memory update.

- **0.3.0 released (2026-11-07, owner: "yes release as 0.3.0"), tag → `1fe255f`.** Version
  decision: the gate's floor against v0.2.1 was **major** (SPEC 3.0.0 → 4.0.0; `wasmImport` /
  `createSingleton` / `InstancePool.new` changed by `options`), so a pre-1.0 Rule 6 **minor** with
  the Breaking Changes row. `bump.dart minor` allowed it (v0.2.1's tests 9/9 on the new code). CI
  run 42436175882 green in both jobs ([releasing.md](releasing.md)); pub.dev read back: latest
  0.3.0, published 2026-11-08T01:55Z (UTC); GitHub release `v0.3.0` exists.
- **C30 → `publish.yml` split into two jobs (`cb7bc26`, owner: "I agree with splitting into two
  jobs if it will maintain better privacy").** Findings (1) and (2) did not apply as written (no
  `id-token: write`, no `concurrency:`), and (3) did not apply (no Bun). The one job used to run
  third-party package code and then write `PUB_DEV_CREDENTIALS` on the same runner. Now `checks`
  (read-only token, no secret) is separate from `publish` (SDK only; since the H32 pass of
  2026-11-09 the page comes from a third job, `release`; before that the GitHub Release went
  through the CLI until the H30 change of 2026-11-09). Its first real run
  was 0.3.0's, green.

- **C29 / H29 → SPEC 4.0.0 (2026-11-07, owner: "make the requested fixes"), `aa1af8d` + `5e24ae3`,
  released in 0.3.0 (entry above).** What 0.2.1 did, READ from its code (`bf049de`), not run one by one: a `.wit`
  answering 500 or a network error → raw exports, silently (the H29 S10 half); `parseWit` read `u32`
  as `s32` and skipped a malformed parameter; a missing callback → `0`, a `null` / `true` callback
  result → encoded as `0` / `1`; `add(1)` passed a `null`; `greet(42)` sent `"42"`; an `s64`
  argument went in as a JS number, which an i64 parameter refuses; no time limit at all. MEASURED:
  the 14 new non-http refusal tests are red on 0.2.1's `lib/` ([testing.md](testing.md)). All now refused
  per -js `SPEC.md` 4.0.0 §§ 2, 4, 11 (the details in [overview.md](overview.md) § Conformance; the
  tests in [testing.md](testing.md)).

- **H19 force-pushed 2026-10-26** (owner: "try the force push"): `main` → `0bcd2e9` and the three
  tags, each with a lease on its old value; GitHub accepted all four (no immutable release);
  `ls-remote` = local; all 22 pushed commits re-scanned with `-a`, 0 hits. The tag moves re-ran
  `publish.yml` three times (runs 40383568732 for v0.1.0, 40383568400 for v0.2.1, and one for v0.2.0): every step green up to
  **"Publish to pub.dev" — failed (version exists)**, "Create GitHub Release" skipped; pub.dev
  read back unchanged (latest 0.2.1, original publish dates). Expected and harmless, as predicted.
- **Workspace letters, 2026-10-26** (owner: "perform H19 and C11/H7 and C8"; one commit after the
  purge): **H19** history purged of the drive path, verified pair by pair
  ([history-map-2026-10-26.md](history-map-2026-10-26.md)); **H18 / H25 §3(c)** `CLAUDE.md` clean at
  HEAD; **H16** `maintenance.strategy gc` (1 pack); **H22 / H25 §3(d)** path test recorded
  ([working-rules.md](working-rules.md) § Privacy); **H24 + C8 + H27** ★ block re-copied (5.2,
  6.1) and re-stamped `Copied from synapticforge1/…` after a 28 = 28 / 0-difference text check
  ([best-practices.md](best-practices.md)); **C11 / H7** fixtures re-stamped to wasmtk
  `4a5c3cf668d`, bytes proven identical by rebuilding, then `-js` `36aa661`'s stamp copied verbatim
  ([testing.md](testing.md)). Record-only: **H15** conforms (Dart scripts since `3883d61`); **H20**
  pub.dev published 0.2.1 after the org move; **H28** the email exception widened
  ([working-rules.md](working-rules.md) § Privacy; this repo keeps the address on commits only).
  **The pull line** (owner: "fix the handoff notation", 2026-10-26): `CLAUDE.md` now reads
  `workspace-correspondence.md` first, then `handoffs.md`, as INDEX and working-rules do.
- **0.2.1 released (2026-10-22, owner: "bump and push"), tag → `ae231db`:** README §10 correction,
  stamped fixtures, and the first release through the gate ([releasing.md](releasing.md)).
- **H6 (2026-10-22, `41b9fda`):** SemVer gate ([compat-gate.md](compat-gate.md)); ★ block copied
  ([best-practices.md](best-practices.md)); memory split per `memory-conventions.md`; tooling rules
  ([working-rules.md](working-rules.md)). `bump.dart` was already plain SemVer.
- **H7 / S4 (2026-10-22, `c7b37f6`):** fixtures = the stamped `-js` set ([testing.md](testing.md)).
- **Org transfer (2026-10-20, `733f54d`)**, Dart-only scripts (`3883d61`), LF (`18a2559`), 0.2.0 release
  (`5f1c294`).
