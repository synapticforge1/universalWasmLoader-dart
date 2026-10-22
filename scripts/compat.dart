// The compatibility gate (workspace `layout-and-packaging.md` § "The
// compatibility gate"; letter H6, 2026-10-22). "Backward compatible" is a gate
// result, never a judgment made at bump time. Mirrors the `-js` reference's
// `scripts/compat.ts`.
//
// - Rule 2, the FLOOR: the surface (surface.dart) at the last release tag
//   against the working tree's. Anything removed or changed → major; added →
//   minor; nothing → patch. The SPEC version moves it by its own level
//   (lowered → major). A changed signature is major even when it widens: the
//   gate cannot tell widening from narrowing, so it errs high.
// - Rule 3, BEHAVIOUR: the previous tag's `test/` (test files AND fixtures,
//   unmodified) runs against the NEW `lib/` in Chrome. Required green for a
//   patch or minor.
// - Rules 4 + 6: when the floor is major, README's `### ⚠️ Breaking Changes`
//   table must carry a row for the release (`_next release_` before the bump,
//   the version after it). Pre-1.0 (0.y.z) a minor is allowed where the floor
//   says major; the row is still mandatory.
//
// Run via:  dart run scripts/compat.dart                    # report vs last tag
//           dart run scripts/compat.dart --against v0.1.0   # vs an older tag
//           dart run scripts/compat.dart --release          # CI, on the tag
//
// `dart run scripts/bump.dart` runs the same checks before it raises the version.

import 'dart:io';

import 'surface.dart';

const rank = {'patch': 0, 'minor': 1, 'major': 2};

/// The project root (this script's parent directory), as a directory URI.
final Uri root = File.fromUri(Platform.script).parent.parent.uri;

/// `X.Y.Z` as three numbers; throws on anything else.
List<int> parseVersion(String v) {
  final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(v);
  if (m == null) throw FormatException('not an X.Y.Z version: "$v"');
  return [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
}

/// The level by which [to] raises [from]; throws when it does not raise it.
String bumpKind(String from, String to) {
  final a = parseVersion(from);
  final b = parseVersion(to);
  const kinds = ['major', 'minor', 'patch'];
  for (var i = 0; i < 3; i++) {
    if (b[i] > a[i]) return kinds[i];
    if (b[i] < a[i]) break;
  }
  throw FormatException('version $to does not raise $from');
}

/// The minimum bump the change from [old] to [cur] requires, and why.
({String floor, List<String> reasons}) floorOf(Surface old, Surface cur) {
  final reasons = <String>[];
  var floor = 'patch';
  void raise(String kind, String why) {
    reasons.add('$kind: $why');
    if (rank[kind]! > rank[floor]!) floor = kind;
  }

  if (old.spec != cur.spec) {
    try {
      raise(bumpKind(old.spec, cur.spec), 'SPEC.md ${old.spec} → ${cur.spec}');
    } on FormatException {
      raise('major', 'SPEC.md ${old.spec} → ${cur.spec} (lowered)');
    }
  }
  old.symbols.forEach((k, was) {
    final now = cur.symbols[k];
    if (now == null) {
      raise('major', 'symbol removed: $k');
    } else if (now != was) {
      raise('major', 'symbol changed: $k\n      was: $was\n      now: $now');
    }
  });
  for (final k in cur.symbols.keys) {
    if (!old.symbols.containsKey(k)) raise('minor', 'symbol added: $k');
  }
  return (floor: floor, reasons: reasons);
}

/// Whether README's `### ⚠️ Breaking Changes` table has a row for [label].
bool hasBreakingRow(String readme, String label) {
  final start = readme.indexOf('### ⚠️ Breaking Changes');
  if (start < 0) return false;
  // The section body starts after the heading line, ends at the next heading.
  final eol = readme.indexOf('\n', start);
  if (eol < 0) return false;
  final rest = readme.substring(eol + 1);
  final end = rest.indexOf(RegExp(r'^#', multiLine: true));
  final section = end < 0 ? rest : rest.substring(0, end);
  return section.split('\n').any((l) => l.startsWith('| $label |'));
}

/// The problems that block a bump of [kind] from version [from] (none =
/// allowed); [kind] null is a report. Pure, so the self-test can drive it.
List<String> problemsFor({
  required String floor,
  required bool testsOk,
  required bool surfaceCurrent,
  required String? kind,
  required String from,
  required String readme,
  required String rowLabel,
}) {
  final problems = <String>[];
  if (!surfaceCurrent) {
    problems.add(
      'api-surface.json is stale: re-baseline it in its own commit first '
      '(`dart run scripts/surface.dart`), stating the reason',
    );
  }
  if (kind != null) {
    final preOne = parseVersion(from)[0] == 0;
    if (rank[kind]! < rank[floor]!) {
      final exempt = preOne && floor == 'major' && kind == 'minor';
      if (!exempt) problems.add('a $kind bump is below the floor ($floor)');
    }
    if (kind != 'major' && !testsOk) {
      problems.add(
        "the previous tag's tests are red, so a $kind is not allowed: classify "
        'each failure (a test that must change is a surface change)',
      );
    }
  }
  if (floor == 'major' && !hasBreakingRow(readme, rowLabel)) {
    problems.add(
      'the floor is major: README `### ⚠️ Breaking Changes` needs a row '
      '`| $rowLabel | <what changed> | <how to migrate> |`',
    );
  }
  return problems;
}

String git(List<String> args, {Uri? dir}) {
  final r = Process.runSync('git', args,
      workingDirectory: Directory.fromUri(dir ?? root).path);
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')}: ${(r.stderr as String).trim()}');
  }
  return (r.stdout as String).trim();
}

/// The newest release tag reachable from [rev].
String lastTag([String rev = 'HEAD']) =>
    git(['describe', '--tags', '--abbrev=0', '--match', 'v[0-9]*', rev]);

/// Runs [body] in a throwaway worktree of [tag], removed afterwards.
Future<T> withWorktree<T>(
    String tag, Future<T> Function(Directory) body) async {
  final dir = Directory.systemTemp.createTempSync('uwl-compat-');
  git(['worktree', 'add', '--detach', dir.path, tag]);
  try {
    return await body(dir);
  } finally {
    git(['worktree', 'remove', '--force', dir.path]);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

ProcessResult dart(List<String> args, Directory dir) =>
    Process.runSync(Platform.resolvedExecutable, args,
        workingDirectory: dir.path);

void pubGet(Directory dir) {
  final r = dart(['pub', 'get'], dir);
  if (r.exitCode != 0) {
    throw StateError('dart pub get in ${dir.path}: ${r.stderr}');
  }
}

/// Copies every file under [from] to the same relative path under [to].
void copyDir(Directory from, Directory to) {
  final base = from.absolute.uri;
  var copied = 0;
  for (final e in from.listSync(recursive: true).whereType<File>()) {
    final rel = e.absolute.uri.path.substring(base.path.length);
    final target = File.fromUri(to.absolute.uri.resolve('./').resolve(rel));
    target.parent.createSync(recursive: true);
    e.copySync(target.path);
    copied++;
  }
  if (copied == 0) throw StateError('copyDir: nothing under ${from.path}');
}

/// The surface of a release tag, generated from its own tree.
Future<Surface> surfaceAt(String tag) => withWorktree(tag, (dir) async {
      pubGet(dir);
      return surfaceOf(dir.uri);
    });

/// Rule 3: the tag's `test/` against the current `lib/` + `pubspec.yaml`.
Future<({bool ok, String summary})> previousTests(String tag) =>
    withWorktree(tag, (dir) async {
      final lib = Directory('${dir.path}/lib')..deleteSync(recursive: true);
      copyDir(Directory.fromUri(root.resolve('lib/')), lib);
      File.fromUri(root.resolve('pubspec.yaml'))
          .copySync('${dir.path}/pubspec.yaml');
      pubGet(dir);
      final r = dart(['test', '-p', 'chrome', '--reporter', 'expanded'], dir);
      final out = '${r.stdout}\n${r.stderr}';
      final m = RegExp(
              r'\+(\d+)(?: ~\d+)?(?: -(\d+))?: (?:All tests passed!|Some tests failed\.)')
          .allMatches(out)
          .lastOrNull;
      final pass = int.tryParse(m?.group(1) ?? '') ?? 0;
      final fail = int.tryParse(m?.group(2) ?? '0') ?? 0;
      final ok = r.exitCode == 0 && pass > 0 && fail == 0;
      if (!ok) {
        final lines = out.trim().split('\n');
        stderr.writeln('  --- previous-tag test output (last 15 lines) ---');
        stderr.writeln(
            lines.skip(lines.length > 15 ? lines.length - 15 : 0).join('\n'));
      }
      final counts = m == null ? 'no summary line' : '$pass pass, $fail fail';
      return (ok: ok, summary: '$tag test/: $counts (exit ${r.exitCode})');
    });

/// Prints the evaluation against [tag]; returns the blocking problems.
Future<List<String>> judge(
  String tag, {
  required String? kind,
  required String from,
  required String rowLabel,
}) async {
  final cur = await surfaceOf(root);
  final committed = File.fromUri(root.resolve('api-surface.json'));
  final surfaceCurrent = committed.existsSync() &&
      committed.readAsStringSync().replaceAll('\r\n', '\n') == cur.render();
  final (:floor, :reasons) = floorOf(await surfaceAt(tag), cur);
  final tests = await previousTests(tag);

  print('compatibility gate against $tag');
  print('  floor: $floor');
  for (final r in reasons) {
    print('    $r');
  }
  print(
      "  previous-tag tests: ${tests.ok ? 'green' : 'RED'} — ${tests.summary}");
  print("  api-surface.json: ${surfaceCurrent ? 'current' : 'STALE'}");
  return problemsFor(
    floor: floor,
    testsOk: tests.ok,
    surfaceCurrent: surfaceCurrent,
    kind: kind,
    from: from,
    readme: File.fromUri(root.resolve('README.md')).readAsStringSync(),
    rowLabel: rowLabel,
  );
}

/// The `version:` of pubspec.yaml.
String pubspecVersion() {
  final m = RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(
      File.fromUri(root.resolve('pubspec.yaml')).readAsStringSync());
  if (m == null) throw StateError('no `version:` line in pubspec.yaml');
  return m.group(1)!;
}

void reportBlocked(List<String> problems) {
  stderr.writeln('\nBLOCKED:');
  for (final p in problems) {
    stderr.writeln('  $p');
  }
}

Future<void> main(List<String> args) async {
  final version = pubspecVersion();
  final List<String> problems;
  if (args.contains('--release')) {
    // On the tag being published: compare with the release before it.
    final tags = git(['tag', '--points-at', 'HEAD']).split('\n');
    final prev = lastTag('HEAD^');
    final kind = bumpKind(prev.substring(1), version);
    print('release $prev → v$version is a $kind');
    problems = [
      if (!tags.contains('v$version'))
        'HEAD is not tagged v$version (tags here: ${tags.join(', ')})',
      ...await judge(prev,
          kind: kind, from: prev.substring(1), rowLabel: version),
    ];
  } else {
    final at = args.indexOf('--against');
    final tag = at >= 0 && at + 1 < args.length ? args[at + 1] : lastTag();
    problems =
        await judge(tag, kind: null, from: version, rowLabel: '_next release_');
  }
  if (problems.isNotEmpty) {
    reportBlocked(problems);
    exit(1);
  }
}
