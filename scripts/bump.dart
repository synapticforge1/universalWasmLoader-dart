// Raises the `version:` field in pubspec.yaml (the single version source),
// after the compatibility gate allows it (scripts/compat.dart; workspace
// letter H6): a bump below the floor, or a patch/minor with the previous
// tag's tests red, is refused.
//
// Run via:  dart run scripts/bump.dart           # patch:  0.1.0 → 0.1.1
//           dart run scripts/bump.dart minor      # minor:  0.1.0 → 0.2.0
//           dart run scripts/bump.dart major      # major:  0.1.0 → 1.0.0
//
// Mirrors the `-js` reference's `scripts/bump.ts`: a targeted single-line edit
// so the rest of pubspec.yaml's formatting is untouched. On success it also
// stamps the new version over README's `| _next release_ |` Breaking Changes
// row and CHANGELOG's `## Unreleased` heading, when present.

import 'dart:io';

import 'compat.dart';

Future<void> main(List<String> args) async {
  final kind = (args.isEmpty ? 'patch' : args[0]).toLowerCase();
  if (kind != 'patch' && kind != 'minor' && kind != 'major') {
    stderr.writeln(
      '❌ bump: unknown release kind "$kind" — use patch | minor | major',
    );
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
