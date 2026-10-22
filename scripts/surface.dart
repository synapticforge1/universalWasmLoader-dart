// Generates the package SURFACE — what consumers can depend on — never written
// by hand (compatibility gate Rule 1, workspace `layout-and-packaging.md`
// § "The compatibility gate"; letter H6, 2026-10-22).
//
// Run via:  dart run scripts/surface.dart           # rewrite api-surface.json
//           dart run scripts/surface.dart --check   # fail if it is stale
//
// The surface is: the `SPEC.md` version the README declares, and every name
// each public library in `lib/` (not `lib/src/`) exports — one key per symbol
// and one per public member, valued by the analyzer's signature for it.
// Mirrors the `-js` reference's `scripts/surface.ts`. A declaration kind it
// cannot key FAILS the run rather than being skipped: an unseen symbol is an
// unchecked one.

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';

/// The generated surface. Keys are sorted so the JSON diffs cleanly.
class Surface {
  Surface(this.spec, Map<String, String> symbols)
      : symbols = Map.fromEntries(
          symbols.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
        );

  final String spec;
  final Map<String, String> symbols;

  String render() => '${const JsonEncoder.withIndent('  ').convert({
            'spec': spec,
            'symbols': symbols
          })}\n';
}

/// The SPEC version declared once in README.md as `SPEC.md` **vX.Y.Z**.
String specVersionOf(Uri root) {
  final readme = File.fromUri(root.resolve('README.md')).readAsStringSync();
  final m = RegExp(r'`SPEC\.md`\s+\*\*v(\d+\.\d+\.\d+)\*\*')
      .allMatches(readme)
      .toList();
  if (m.length != 1) {
    throw StateError(
      'README.md must declare the SPEC version exactly once as '
      '`SPEC.md` **vX.Y.Z** (found ${m.length})',
    );
  }
  return m.single.group(1)!;
}

/// The surface of the package rooted at [root] (a directory URI).
Future<Surface> surfaceOf(Uri root) async {
  final libs = Directory.fromUri(root.resolve('lib/'))
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.path)
      .toList()
    ..sort();
  if (libs.isEmpty) throw StateError('no public library in lib/');

  final collection = AnalysisContextCollection(includedPaths: libs);
  final symbols = <String, String>{};
  for (final path in libs) {
    final result = await collection
        .contextFor(path)
        .currentSession
        .getResolvedLibrary(path);
    if (result is! ResolvedLibraryResult) {
      throw StateError('cannot resolve $path: $result');
    }
    final file = path.split(RegExp(r'[\\/]')).last;
    result.element.exportNamespace.definedNames2.forEach((name, e) {
      _key(symbols, '$file $name', e);
    });
  }
  return Surface(specVersionOf(root), symbols);
}

String _sig(Element e) {
  final s = e.displayString();
  // Only a class member can be static; the analyzer also flags top-level ones.
  final member = e.enclosingElement is InstanceElement;
  return member && e is ExecutableElement && e.isStatic ? 'static $s' : s;
}

void _key(Map<String, String> out, String key, Element e) {
  switch (e) {
    case InstanceElement():
      out[key] = _sig(e);
      final members = <Element>[
        if (e is InterfaceElement) ...e.constructors,
        ...e.methods,
        ...e.getters,
        ...e.setters,
      ];
      for (final m in members) {
        if (m.isPrivate) continue;
        final name = m is SetterElement ? '${m.name}=' : m.name;
        if (name == null) throw StateError('unnamed member in $key: $m');
        out['$key.$name'] = _sig(m);
      }
    case TopLevelFunctionElement() ||
          TypeAliasElement() ||
          GetterElement() ||
          SetterElement():
      out[key] = _sig(e);
    default:
      throw UnsupportedError(
        'surface: cannot key $key (${e.runtimeType}); teach surface.dart this '
        'kind rather than skipping it',
      );
  }
}

Future<void> main(List<String> args) async {
  final root = File.fromUri(Platform.script).parent.parent.uri;
  final rendered = (await surfaceOf(root)).render();
  final file = File.fromUri(root.resolve('api-surface.json'));
  if (args.contains('--check')) {
    final committed = file.existsSync()
        ? file.readAsStringSync().replaceAll('\r\n', '\n')
        : '';
    if (committed != rendered) {
      stderr.writeln(
        '❌ api-surface.json is stale: re-baseline it in its own commit '
        '(`dart run scripts/surface.dart`), stating the reason.',
      );
      exit(1);
    }
    print('✅ api-surface.json is current');
    return;
  }
  file.writeAsStringSync(rendered);
  print('api-surface.json: ${jsonDecode(rendered)['symbols'].length} keys');
}
