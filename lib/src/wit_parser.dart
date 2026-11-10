/// WIT (WebAssembly Interface Types) parsing for the loader.
///
/// Parses the small subset of WIT that `wasmtk` emits: a `package` line and a
/// single `world { ... }` block containing `import`/`export` `func` declarations.
library;

/// A single WIT function parameter.
class WitParam {
  /// The camelCase parameter name.
  final String name;

  /// The WIT type token (`s32`, `s64`, `f32`, `f64`, `bool`, `string`).
  final String type;

  /// A parameter named [name] (camelCase) of WIT type [type].
  const WitParam(this.name, this.type);
}

/// A single WIT function declaration (an `import` or an `export`).
class WitFunc {
  /// The raw kebab-case WIT name (e.g. `str-len`, `env-mul`).
  final String name;

  /// The camelCase name used at the call site / for export lookup (e.g. `strLen`).
  final String tsName;

  /// The function parameters in declaration order.
  final List<WitParam> params;

  /// The result WIT type, or `null` for a void function.
  final String? result;

  /// A function declaration, as [parseWit] builds it.
  const WitFunc({
    required this.name,
    required this.tsName,
    required this.params,
    required this.result,
  });
}

/// The result of [parseWit].
class ParsedWit {
  /// The `package` name (e.g. `local:math-50`), or `''` if absent.
  final String packageName;

  /// The `world` name, or `''` if absent.
  final String worldName;

  /// Functions in the WIT `import` section.
  final List<WitFunc> imports;

  /// Functions in the WIT `export` section.
  final List<WitFunc> exports;

  /// A parsed world, as [parseWit] returns it.
  const ParsedWit({
    required this.packageName,
    required this.worldName,
    required this.imports,
    required this.exports,
  });
}

/// Converts a kebab-case WIT name to camelCase (e.g. `str-len` -> `strLen`).
String kebabToCamel(String name) {
  return name.replaceAllMapped(
    RegExp(r'-([a-z0-9])'),
    (m) => m[1]!.toUpperCase(),
  );
}

/// Converts a kebab-case WIT import name to the underscore WASM import key
/// (e.g. `env-mul` -> `env_mul`).
String kebabToWasmImportKey(String name) => name.replaceAll('-', '_');

/// The WIT types this loader translates (SPEC §4); any other type is an error.
const _witTypes = {'s32', 's64', 'f32', 'f64', 'bool', 'string'};

/// A WIT identifier: kebab-case words of letters and digits.
final _ident = RegExp(r'^[A-Za-z][A-Za-z0-9]*(?:-[A-Za-z0-9]+)*$');

/// One `import` / `export` statement of a world body, without its `;`.
final _funcStmt = RegExp(
    r'^(import|export)\s+([^\s:]+)\s*:\s*func\s*\(([^()]*)\)\s*(?:->\s*(\S+))?$');

Never _fault(String what) => throw FormatException(what);

String _parseWitType(String raw, String where) {
  final t = raw.trim();
  if (!_witTypes.contains(t)) {
    _fault('unsupported WIT type "$t" in $where '
        '(supported: ${_witTypes.join(', ')})');
  }
  return t;
}

List<WitParam> _parseWitParams(String raw, String fnLabel) {
  // A trailing comma is valid WIT: `func(a: s32,)`.
  final parts = raw.split(',').map((p) => p.trim()).toList();
  if (parts.isNotEmpty && parts.last.isEmpty) parts.removeLast();
  final out = <WitParam>[];
  final seen = <String>{};
  for (final part in parts) {
    final m = RegExp(r'^([^:\s]+)\s*:\s*(\S+)$').firstMatch(part);
    if (m == null || !_ident.hasMatch(m[1]!)) {
      _fault('malformed parameter "$part" in $fnLabel (expected "name: type")');
    }
    final rawName = m[1]!;
    if (!seen.add(rawName)) {
      _fault('duplicate parameter "$rawName" in $fnLabel');
    }
    final type = _parseWitType(m[2]!, '$fnLabel, parameter $rawName');
    out.add(WitParam(kebabToCamel(rawName), type));
  }
  return out;
}

/// Parses a WIT source string in the subset `wasmtk` writes: an optional
/// `package` line and one `world` holding only `import` / `export` function
/// statements, with `//` line comments.
///
/// Anything else — a malformed statement or parameter, a type outside
/// `s32 s64 f32 f64 bool string`, a duplicate name, text outside the world —
/// throws a [FormatException] naming it (SPEC 4.0.0 §2): a `.wit` is never
/// read loosely.
ParsedWit parseWit(String src) {
  final code = src.replaceFirst(RegExp('^﻿'), '').replaceAll(
        RegExp(r'//[^\n]*'),
        '',
      );

  var rest = code.trim();
  var packageName = '';
  final pkg = RegExp(r'^package\s+([^\s;]+)\s*;').firstMatch(rest);
  if (pkg != null) {
    packageName = pkg[1]!;
    rest = rest.substring(pkg[0]!.length).trim();
  }

  final world = RegExp(r'^world\s+([^\s{]+)\s*\{([^{}]*)\}$').firstMatch(rest);
  if (world == null) {
    final what = rest.isEmpty
        ? 'it is empty'
        : 'expected one "world <name> { ... }" block, found: '
            '${rest.length > 60 ? rest.substring(0, 60) : rest}';
    _fault('not a WIT world: $what');
  }
  final worldName = world[1]!;
  if (!_ident.hasMatch(worldName)) _fault('malformed world name "$worldName"');

  final imports = <WitFunc>[];
  final exports = <WitFunc>[];
  final statements = world[2]!.split(';').map((s) => s.trim()).toList();
  final last = statements.removeLast();
  if (last.isNotEmpty) {
    _fault('unterminated WIT statement (missing ";"): $last');
  }
  for (final stmt in statements) {
    final m = _funcStmt.firstMatch(stmt);
    if (m == null) {
      _fault('unsupported or malformed WIT statement: '
          '${stmt.replaceAll(RegExp(r'\s+'), ' ')}');
    }
    final keyword = m[1]!;
    final name = m[2]!;
    final fnLabel = '$keyword $name';
    if (!_ident.hasMatch(name)) _fault('malformed function name in $fnLabel');
    final list = keyword == 'import' ? imports : exports;
    if (list.any((f) => f.name == name)) _fault('duplicate $fnLabel');
    final params = _parseWitParams(m[3]!, fnLabel);
    final result =
        m[4] != null ? _parseWitType(m[4]!, '$fnLabel, result') : null;
    list.add(WitFunc(
      name: name,
      tsName: kebabToCamel(name),
      params: params,
      result: result,
    ));
  }

  return ParsedWit(
    packageName: packageName,
    worldName: worldName,
    imports: imports,
    exports: exports,
  );
}
