// Pushes the bump commit on `main` to GitHub. CI does the rest, in the owner's
// order (workspace release-process.md § 5, decision D1, 2026-11-10): checks
// first, then CI creates the tag, then the GitHub Release page from the tag,
// then the publish to pub.dev (.github/workflows/publish.yml).
//
// Run via:  dart run scripts/bump.dart <patch|minor|major>   # the bump commit
//           dart run scripts/release.dart [--dry-run]
//
// Guards (U4), each refusing with nothing pushed:
//   - on `main`, the tree clean (untracked files count);
//   - HEAD = GitHub's `main` + exactly one commit, `bump to v<version>`;
//   - the tag v<version> absent here and on GitHub;
//   - pub.dev does not serve <version>;
//   - a cold gate: analyze, the browser suite, the release-script tests,
//     `compat.dart --release`, `dart pub publish --dry-run`.
// Then ONE push of `main` (no tag — CI tags after its checks; never
// `git tag -f`, never a forced push), read back with `git ls-remote`.
// It NEVER publishes: only CI publishes.

import 'dart:io';

void main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  if (args.any((a) => a != '--dry-run')) {
    _fail('usage: dart run scripts/release.dart [--dry-run]');
  }
  // Work from the project root regardless of the caller's cwd.
  Directory.current = File.fromUri(Platform.script).parent.parent;

  final m = RegExp(r'^version:\s*(\d+\.\d+\.\d+)\s*$', multiLine: true)
      .firstMatch(File('pubspec.yaml').readAsStringSync());
  if (m == null) _fail("no 'version: X.Y.Z' in pubspec.yaml");
  final version = m.group(1)!;
  final tag = 'v$version';
  print('release $tag${dryRun ? ' (dry run: nothing is pushed)' : ''}');

  // 1. On main, clean.
  final branch = _git(['rev-parse', '--abbrev-ref', 'HEAD']);
  if (branch != 'main') _fail('on "$branch", not main');
  final dirty = _git(['status', '--porcelain', '--untracked-files=all']);
  if (dirty.isNotEmpty) {
    _fail('the tree is not clean (untracked files count):\n$dirty');
  }

  // 2. HEAD = GitHub's main + exactly the bump commit.
  final remoteMain = _git(['ls-remote', 'origin', 'refs/heads/main'])
      .split(RegExp(r'\s+'))
      .first;
  if (remoteMain.isEmpty) _fail('GitHub has no main branch');
  final parent = _git(['rev-parse', 'HEAD^']);
  final subject = _git(['log', '-1', '--format=%s']);
  if (parent != remoteMain || subject != 'bump to $tag') {
    _fail('HEAD must be GitHub\'s main ($remoteMain) plus exactly the commit '
        '"bump to $tag" (made by scripts/bump.dart); found HEAD^ = $parent, '
        'subject "$subject"');
  }

  // 3. The tag absent here and on GitHub.
  if (_git(['tag', '--list', tag]).isNotEmpty) {
    _fail('tag $tag exists locally; CI makes the tag — remove the local one');
  }
  if (_git(['ls-remote', '--tags', 'origin', 'refs/tags/$tag']).isNotEmpty) {
    _fail('tag $tag already exists on GitHub: $version was released');
  }

  // 4. pub.dev does not serve the version.
  final pub = await _status(Uri.parse(
      'https://pub.dev/api/packages/universal_wasm_loader/versions/$version'));
  if (pub == 200) _fail('pub.dev already serves $version');
  if (pub != 404) _fail('pub.dev answered $pub for $version; cannot tell');
  print('  guards ok: main = GitHub main + "bump to $tag"; $tag absent '
      'here and on GitHub; pub.dev 404');

  // 5. The cold gate.
  _run('dart', ['analyze']);
  _run('dart', ['test', '-p', 'chrome']);
  _run('dart', ['test', '-p', 'vm', 'test/ci_release_test.dart']);
  _run('dart', ['run', 'scripts/compat.dart', '--release']);
  _run('dart', ['pub', 'publish', '--dry-run']);

  if (dryRun) {
    print('dry run: every guard and the gate passed; nothing was pushed');
    return;
  }

  // 6. ONE push of main, read back.
  final head = _git(['rev-parse', 'HEAD']);
  _git(['push', 'origin', 'main']);
  final readBack = _git(['ls-remote', 'origin', 'refs/heads/main'])
      .split(RegExp(r'\s+'))
      .first;
  if (readBack != head) {
    _fail('read-back: GitHub main = $readBack, expected $head');
  }
  print('');
  print('✅ pushed main = $head (read back with ls-remote); no tag pushed.');
  print('   CI (publish.yml) now runs checks → tag $tag → Release page → '
      'pub.dev, in that order.');
}

Never _fail(String msg) {
  stderr.writeln('❌ release: $msg');
  exit(1);
}

/// `git <args>`, trimmed stdout; fails the release on a non-zero exit.
String _git(List<String> args) {
  final r = Process.runSync('git', args);
  if (r.exitCode != 0) {
    _fail('git ${args.join(' ')}: ${(r.stderr as String).trim()}');
  }
  return (r.stdout as String).trim();
}

/// Runs a gate command with its output shown; fails the release on error.
void _run(String exe, List<String> args) {
  print('  \$ $exe ${args.join(' ')}');
  final r = Process.runSync(exe, args, runInShell: Platform.isWindows);
  if (r.exitCode != 0) {
    stdout.write(r.stdout);
    stderr.write(r.stderr);
    _fail('$exe ${args.join(' ')} failed (exit ${r.exitCode})');
  }
}

/// The HTTP status of a GET, with one 30 s limit for the whole call.
Future<int> _status(Uri url) async {
  final client = HttpClient()
    ..userAgent = 'universalWasmLoader-dart-release'
    ..connectionTimeout = const Duration(seconds: 30);
  try {
    return await () async {
      final res = await (await client.getUrl(url)).close();
      await res.drain<void>();
      return res.statusCode;
    }()
        .timeout(const Duration(seconds: 30));
  } on Exception catch (e) {
    _fail('GET $url failed: $e');
  } finally {
    client.close(force: true);
  }
}
