// Raises the `version:` field in pubspec.yaml (the single version source),
// after the compatibility gate allows it (scripts/compat.dart; workspace
// letter H6): a bump below the floor, or a patch/minor with the previous
// tag's tests red, is refused.
//
// Run via:  dart run scripts/bump.dart patch      # 0.1.0 → 0.1.1
//           dart run scripts/bump.dart minor      # 0.1.0 → 0.2.0
//           dart run scripts/bump.dart major      # 0.1.0 → 1.0.0
//
// The level is the owner's and is REQUIRED: there is no default (workspace
// release-process.md § 5 U1). The tree must be clean, untracked files
// included (U3), and the bump is its own commit, `bump to vX.Y.Z`, made here
// with only the files this script changed (U2). Release notes (CHANGELOG
// `## Unreleased`, a README Breaking Changes row) are merged BEFORE the bump.
//
// A targeted single-line edit keeps the rest of pubspec.yaml's formatting. On
// success it also stamps the new version over README's `| _next release_ |`
// Breaking Changes row and CHANGELOG's `## Unreleased` heading, when present.
// Then `dart run scripts/release.dart` pushes `main`; CI tags and publishes.

import 'dart:io';

import 'compat.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1 ||
      !const {'patch', 'minor', 'major'}.contains(args[0].toLowerCase())) {
    stderr.writeln(
      '❌ bump: the level is required — dart run scripts/bump.dart '
      'patch | minor | major',
    );
    exit(1);
  }
  final kind = args[0].toLowerCase();

  final dirty = git(['status', '--porcelain', '--untracked-files=all']);
  if (dirty.isNotEmpty) {
    stderr.writeln('❌ bump: the tree is not clean (untracked files count); '
        'commit or remove first:\n$dirty');
    exit(1);
  }

  final file = File.fromUri(root.resolve('pubspec.yaml'));
  final text = file.readAsStringSync();
  // Match a top-level `version: X.Y.Z` line (no quotes, YAML style).
  final re =
      RegExp(r'^(version:[ \t]*)(\d+)\.(\d+)\.(\d+)[ \t]*$', multiLine: true);
  final m = re.firstMatch(text);
  if (m == null) {
    stderr.writeln(
      '❌ bump: could not find a `version: X.Y.Z` line in pubspec.yaml',
    );
    exit(1);
  }

  var major = int.parse(m.group(2)!);
  var minor = int.parse(m.group(3)!);
  var patch = int.parse(m.group(4)!);
  final from = '$major.$minor.$patch';

  switch (kind) {
    case 'major':
      major += 1;
      minor = 0;
      patch = 0;
    case 'minor':
      minor += 1;
      patch = 0;
    default:
      patch += 1;
  }
  final to = '$major.$minor.$patch';

  final problems = await judge(
    lastTag(),
    kind: kind,
    from: from,
    rowLabel: '_next release_',
  );
  if (problems.isNotEmpty) {
    reportBlocked(problems);
    stderr.writeln('❌ bump: $from → $to refused; nothing was changed.');
    exit(1);
  }

  // Check every stamp target before writing anything, so a refusal leaves
  // no half-applied bump.
  final stamps = [
    _stamp('README.md', '| _next release_ |', '| $to |'),
    _stamp('CHANGELOG.md', '## Unreleased', '## $to'),
  ];
  file.writeAsStringSync(text.replaceFirst(re, '${m.group(1)}$to'));
  for (final apply in stamps) {
    apply();
  }
  print('✅ pubspec.yaml  → $to  ($kind bump from $from)');

  // The bump commit: only what this script changed.
  git(['add', '--', 'pubspec.yaml', 'README.md', 'CHANGELOG.md']);
  git(['commit', '-q', '-m', 'bump to v$to']);
  print(
      '✅ committed "bump to v$to" (${git(['rev-parse', '--short', 'HEAD'])}); '
      'next: dart run scripts/release.dart');
}

/// Prepares replacing [from] with [to] in [name] when present; exits if it
/// appears more than once. Returns the write to run once all checks pass.
void Function() _stamp(String name, String from, String to) {
  final f = File.fromUri(root.resolve(name));
  final text = f.readAsStringSync();
  final n = from.allMatches(text).length;
  if (n > 1) {
    stderr.writeln('❌ bump: "$from" appears $n times in $name; fix it by hand');
    exit(1);
  }
  return () {
    if (n == 0) return;
    f.writeAsStringSync(text.replaceFirst(from, to));
    print('   $name: "$from" → "$to"');
  };
}
