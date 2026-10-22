// Fails unless test/fixtures/ is exactly the stamped reference set.
//
// Run via:  dart run scripts/check_fixtures.dart
//
// Mirrors the `-js` reference's `scripts/check-fixtures.ts` (workspace letter
// H7 / divergence S4). `test/fixtures/fixtures.json` is a verbatim copy of
// `-js`'s `tests/fixtures.json`; every file it lists must be present and
// sha256-identical, and no `.wasm` / `.wit` / `.wat` may sit there unlisted.
// Never edit a fixture by hand: copy the bytes and the stamp from `-js`.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

void main() {
  // Work from the project root regardless of the caller's cwd.
  Directory.current = File.fromUri(Platform.script).parent.parent;

  final dir = Directory('test/fixtures');
  final stamp = jsonDecode(File('${dir.path}/fixtures.json').readAsStringSync())
      as Map<String, dynamic>;
  final files = (stamp['files'] as Map<String, dynamic>).cast<String, String>();
  final generator = stamp['generator'] as Map<String, dynamic>;

  final problems = <String>[];
  files.forEach((name, hash) {
    final f = File('${dir.path}/$name');
    if (!f.existsSync()) {
      problems.add('$name: missing');
    } else if (sha256.convert(f.readAsBytesSync()).toString() != hash) {
      problems.add('$name: bytes differ from the stamp');
    }
  });
  for (final e in dir.listSync().whereType<File>()) {
    final name = e.uri.pathSegments.last;
    if (RegExp(r'\.(wasm|wit|wat)$').hasMatch(name) &&
        !files.containsKey(name)) {
      problems.add('$name: not in the stamp');
    }
  }

  if (problems.isNotEmpty) {
    stderr.writeln('❌ Fixtures do not match test/fixtures/fixtures.json:');
    for (final p in problems) {
      stderr.writeln('  $p');
    }
    stderr.writeln(
      'Copy the bytes and fixtures.json from universalWasmLoader-js tests/; '
      'never edit a fixture by hand.',
    );
    exit(1);
  }
  print(
    '✅ ${files.length} fixtures match the stamp (wasmtk '
    '${generator['describe']}, ${(generator['commit'] as String).substring(0, 11)})',
  );
}
