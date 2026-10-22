// Tags vX.Y.Z from the current pubspec.yaml version and pushes the tag, which
// triggers .github/workflows/publish.yml to publish to pub.dev.
//
// Run via:  dart run scripts/release.dart   # commit any pending pubspec bump, tag, push
//
// Mirrors the `-js` reference's `scripts/publish.ts`: this NEVER runs
// `dart pub publish` locally — it only tags + pushes so CI does the publish.

import 'dart:io';

void main() {
  // Work from the project root regardless of the caller's cwd.
  Directory.current = File.fromUri(Platform.script).parent.parent;

  final file = File('pubspec.yaml');
  final m = file.existsSync()
      ? RegExp(r'^version:\s*(\d+\.\d+\.\d+)\s*$', multiLine: true)
          .firstMatch(file.readAsStringSync())
      : null;
  if (m == null) {
    stderr.writeln("❌ release: no 'version:' in pubspec.yaml");
    exit(1);
  }
  final tag = 'v${m.group(1)}';

  print('Releasing $tag via GitHub Actions…');

  // Commit a pending pubspec.yaml version change, if any.
  if (_git(['diff', '--quiet', '--', 'pubspec.yaml'], check: false) != 0) {
    _git(['add', 'pubspec.yaml']);
    _git(['commit', '-m', 'bump version to $tag']);
  }

  _git(['tag', '-f', tag]);
  _git(['push']);
  _git(['push', '-f', 'origin', tag]);

  print('');
  print(
      'Tag $tag pushed. GitHub Actions (publish.yml) will publish to pub.dev.');
}

/// Runs `git <args>`, echoing its output; exits on failure unless [check] is false.
int _git(List<String> args, {bool check = true}) {
  final r = Process.runSync('git', args);
  stdout.write(r.stdout);
  stderr.write(r.stderr);
  if (check && r.exitCode != 0) {
    stderr.writeln(
        '❌ release: git ${args.join(' ')} failed (exit ${r.exitCode})');
    exit(r.exitCode);
  }
  return r.exitCode;
}
