# History map — the 2026-10-26 path purge (workspace letters H18 / H19 / H25 §3)

**Why:** `CLAUDE.md` carried the owner's real workspace path (a `safe.directory` example, in two
variants: the old `GithubProjects` and `wasmExamples` folders) in **every one of the 19 commits** and
at HEAD. Nothing else matched: a binary-aware scan (`git grep -a`) of every commit's tree, and of
every commit and tag message, found only that line; the `%APPDATA%` hits in `README.md` /
`overview.md` are convention paths, kept. `.pubignore` has excluded `CLAUDE.md` since `v0.1.0`, so no
pub.dev archive ever carried it.

**What was done (owner: "perform H19", 2026-10-26):** a pre-purge bundle of every ref (private,
`cmem/local/backups/`); `git filter-branch --index-filter` over `--branches --tags` that rewrote
ONLY the `CLAUDE.md` blob, replacing the path with `<repo-root>`; author / committer (the allowed
maintainer address) untouched. **Verified pair by pair:** each new commit's header (author,
committer, dates) and message are identical to the old one, and `git diff old new` is exactly
1 line of `CLAUDE.md`; a re-scan of every rewritten ref finds 0 hits. Then `refs/original` deleted,
reflogs expired, `git gc --prune=now`, `fsck` clean, `maintenance.strategy gc` set (H16; 1 pack).
**Tagged trees changed** (they held `CLAUDE.md`); the published pub.dev archives did not, since they
never included it. GitHub keeps serving the old commits by hash until its GC (removal is a GitHub
Support request, the owner's).

**Pushed 2026-10-26** (owner: "try the force push"): `main` and the three tags with
`--force-with-lease` on each old value; all accepted; `ls-remote` read back equal to local; every
pushed commit re-scanned (`-a`), 0 hits. ⚠️ **A moved `v*` tag re-runs `publish.yml`:** three runs,
each failing at "Publish to pub.dev" (version exists) with "Create GitHub Release" skipped; pub.dev
unchanged. Any future tag rewrite here does the same.

**Map (old → new), oldest first; tags marked:**

| old | new | |
| --- | --- | --- |
| `c7884df` | `720231c` | |
| `e75c046` | `e71930f` | |
| `6aa6fb0` | `ec4e41c` | |
| `b62fdeb` | `c9ed7b1` | |
| `edd1e46` | `4376a8a` | `v0.1.0` |
| `2429345` | `081a4bb` | |
| `985039f` | `6579312` | |
| `4a9b9b7` | `733f54d` | |
| `df673dc` | `26d1361` | |
| `99edd40` | `f3f4cf7` | |
| `a75b167` | `3883d61` | |
| `e5529e4` | `09bd38a` | |
| `f550a37` | `5f1c294` | `v0.2.0` |
| `b9f4e9c` | `18a2559` | |
| `11dacb9` | `73ad396` | |
| `bc53669` | `c7b37f6` | |
| `36378fd` | `41b9fda` | |
| `1fc0757` | `ae231db` | `v0.2.1` |
| `256c699` | `c27fa82` | |

Every id quoted in `cmem/` was translated through this table the same day. The workspace letters
quote the OLD ids (`36378fd`, `bc53669`, `1fc0757`); they are history there and resolve through
this table.
