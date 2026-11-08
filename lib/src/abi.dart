/// Canonical ABI (wasmtime profile) translation between Dart and WASM.
///
/// Mirrors the behavior of the reference loader's `abi.js`: numerics pass
/// through, `bool` maps to `1/0` <-> `true/false`, and `string` flattens to a
/// `(ptr, len)` pair using `cabi_realloc` (params) / callee-allocated returns
/// with `cabi_post_<name>` (returns).
///
/// SPEC 4.0.0 §4: typed-call arguments and host-callback results are checked
/// against the WIT signature and never coerced; every WIT import needs a host
/// callback; every WIT export must exist in the module.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'wasm_interop.dart';
import 'wit_parser.dart';

/// A mutable reference to the active WASM linear memory.
///
/// Set [current] to `instance.exports.memory` after instantiation so that
/// string-param host imports can decode from linear memory.
class MemRef {
  /// The active memory, or `null` before instantiation / for memory-less modules.
  WasmMemory? current;
}

/// The `env` import object plus its [MemRef], built from the WIT `import` list.
class ImportEnv {
  /// The JS object to register under the `env` namespace at instantiation.
  final JSObject env;

  /// The memory reference shared with string-param import wrappers.
  final MemRef memRef;

  const ImportEnv(this.env, this.memRef);
}

const _s32Min = -2147483648;
const _s32Max = 2147483647;
final _s64Min = BigInt.parse('-9223372036854775808');
final _s64Max = BigInt.parse('9223372036854775807');

/// Whether [v] is a 64-bit signed integer value (an `int`, or a `BigInt` in
/// the s64 range). On the web an `int` is a JS number, exact up to 2^53.
bool _isS64(Object? v) {
  if (v is int) {
    final b = BigInt.from(v);
    return b >= _s64Min && b <= _s64Max;
  }
  return v is BigInt && v >= _s64Min && v <= _s64Max;
}

/// What a value of WIT type [type] must be, or `null` when [v] is one
/// (SPEC 4.0.0 §4: checked, never coerced).
String? _domainProblem(String type, Object? v) {
  switch (type) {
    case 's32':
      return v is int && v >= _s32Min && v <= _s32Max
          ? null
          : 'an int in [-2147483648, 2147483647]';
    case 's64':
      return _isS64(v) ? null : 'an int or a BigInt in [-2^63, 2^63 - 1]';
    case 'f32':
    case 'f64':
      return v is num ? null : 'a num';
    case 'bool':
      return v is bool ? null : 'a bool';
    case 'string':
      return v is String ? null : 'a String';
  }
  // The parser admits only the six types above.
  throw StateError('wasmImport: unknown WIT type "$type"');
}

/// The value's kind, computed here rather than from `runtimeType` (minified
/// builds rename types).
String _kind(Object? v) {
  if (v == null) return 'null';
  if (v is bool) return 'bool';
  if (v is int) return 'int';
  if (v is double) return 'double';
  if (v is String) return 'String';
  if (v is BigInt) return 'BigInt';
  if (v is Future) return 'Future';
  if (v is Function) return 'Function';
  return 'object';
}

String _show(Object? v) {
  if (v == null) return 'null';
  if (v is String) return jsonEncode(v);
  if (v is Future || v is Function) return 'a ${_kind(v)}';
  return '$v (${_kind(v)})';
}

String _signature(WitFunc fn) =>
    '${fn.tsName}(${fn.params.map((p) => '${p.name}: ${p.type}').join(', ')})';

@JS('BigInt')
external JSBigInt _jsBigInt(JSString decimal);

@JS('String')
external JSString _jsString(JSAny? v);

/// Encodes a checked numeric / bool value of WIT type [type] for WASM.
JSAny? _encodeScalar(String type, Object v) {
  switch (type) {
    case 'bool':
      return ((v as bool) ? 1 : 0).toJS;
    case 's64':
      return _jsBigInt(v.toString().toJS);
    default:
      return (v as num).toJS;
  }
}

/// Decodes a raw WASM value of (non-string) WIT type [type] for Dart.
Object? _decodeScalar(String type, JSAny? raw) {
  switch (type) {
    case 'bool':
      return (raw as JSNumber).toDartInt != 0;
    case 's64':
      return BigInt.parse(_jsString(raw).toDart);
    case 's32':
      return (raw as JSNumber).toDartInt;
    default:
      return (raw as JSNumber).toDartDouble;
  }
}

String _importLabel(WitFunc fn) => 'host callback ${fn.tsName} '
    '(WIT import "${fn.name}"${fn.result != null ? ' -> ${fn.result}' : ''})';

/// Checks a host callback's return value against its WIT import's result and
/// encodes it for WASM (SPEC 4.0.0 §4: the argument domains in reverse). A void
/// import ignores the value; a `Future` is refused for every import, since WASM
/// cannot wait for it.
JSAny? _encodeCallbackResult(WitFunc fn, Object? ret) {
  if (ret is Future) {
    throw ArgumentError('wasmImport: ${_importLabel(fn)} returned a Future; '
        'host callbacks must be synchronous (WASM cannot wait for it)');
  }
  final result = fn.result;
  if (result == null) return null;
  final expected = _domainProblem(result, ret);
  if (expected != null) {
    throw ArgumentError('wasmImport: ${_importLabel(fn)} returned '
        '${_show(ret)}; expected $expected');
  }
  return _encodeScalar(result, ret!);
}

String _names(Iterable<WitFunc> fns) =>
    fns.map((fn) => '${fn.tsName} (WIT "${fn.name}")').join(', ');

/// Builds the WASM `env` import object for the Canonical ABI (wasmtime) profile.
///
/// [userCallbacks] is keyed by the camelCase WIT name (e.g. `envMul`); the WASM
/// import key is the underscore form (e.g. `env_mul`).
///
/// Every WIT import needs a callback: a missing one throws an [ArgumentError]
/// here, at load time, naming all of them (SPEC 4.0.0 §4). An import with a
/// `string` result throws an [UnsupportedError] here too. A callback's return
/// value is checked when the module calls it.
ImportEnv buildComponentImportEnv(
  List<WitFunc> importFuncs,
  Map<String, Function> userCallbacks,
) {
  final missing =
      importFuncs.where((fn) => !userCallbacks.containsKey(fn.tsName));
  if (missing.isNotEmpty) {
    throw ArgumentError('wasmImport: no host callback for WIT '
        'import${missing.length > 1 ? 's' : ''}: ${_names(missing)}');
  }
  final stringResult = importFuncs.where((fn) => fn.result == 'string');
  if (stringResult.isNotEmpty) {
    throw UnsupportedError('wasmImport: a WIT import returning a string is '
        'not supported: ${_names(stringResult)}');
  }

  final memRef = MemRef();
  final env = JSObject();
  const dec = Utf8Decoder();

  for (final fn in importFuncs) {
    final wasmKey = kebabToWasmImportKey(fn.name);
    final cb = userCallbacks[fn.tsName]!;
    final params = fn.params;

    // The WASM module calls each import with the *flattened* ABI arity (strings
    // expand to a (ptr,len) pair). The closure passed to `.toJS` must therefore
    // accept that exact number of positional args; the dart2js interop
    // trampoline matches arity strictly. We build a wrapper of the right arity
    // by making every slot an optional positional parameter and ignoring the
    // unused tail.
    JSAny? handle(List<JSAny?> raw) {
      final args = <Object?>[];
      var i = 0;
      for (final p in params) {
        if (p.type == 'string') {
          final mem = memRef.current;
          if (mem == null) {
            throw StateError('wasmImport: import "${fn.name}" received a '
                'string before the module\'s memory was available (the '
                'module exports no `memory`, or calls it from its start '
                'function)');
          }
          final ptr = (raw[i++] as JSNumber).toDartInt;
          final len = (raw[i++] as JSNumber).toDartInt;
          args.add(dec.convert(memoryBytes(mem).sublist(ptr, ptr + len)));
        } else {
          args.add(_decodeScalar(p.type, raw[i++]));
        }
      }
      return _encodeCallbackResult(fn, Function.apply(cb, args));
    }

    JSAny? wrapper([
      JSAny? a0,
      JSAny? a1,
      JSAny? a2,
      JSAny? a3,
      JSAny? a4,
      JSAny? a5,
      JSAny? a6,
      JSAny? a7,
    ]) =>
        handle([a0, a1, a2, a3, a4, a5, a6, a7]);

    jsSet(env, wasmKey.toJS, wrapper.toJS);
  }

  return ImportEnv(env, memRef);
}

/// Marks an omitted optional positional slot of a [ModuleExports.function]
/// closure, so an explicit `null` argument stays distinguishable from none.
class _Omitted {
  const _Omitted();
}

const _omitted = _Omitted();

/// A typed handle over raw WASM exports — a map from camelCase export name to a
/// Dart callable applying the Canonical ABI. Also usable as a namespace via
/// [call] (e.g. `mod('greet', ['World'])`) or [function].
class ModuleExports {
  final Map<String, Object? Function(List<Object?>)> _fns;
  final Map<String, Function> _closures = {};

  /// The raw `WebAssembly.Instance.exports` object (escape hatch).
  final JSObject rawExports;

  ModuleExports._(this._fns, this.rawExports);

  /// The camelCase export names this handle exposes.
  Iterable<String> get names => _fns.keys;

  /// Whether an export named [name] exists.
  bool has(String name) => _fns.containsKey(name);

  /// Returns the wrapped callable for [name] (up to 8 positional arguments,
  /// checked as by [call]), or `null` if absent.
  Function? function(String name) {
    final fn = _fns[name];
    if (fn == null) return null;
    return _closures[name] ??= ([
      Object? a0 = _omitted,
      Object? a1 = _omitted,
      Object? a2 = _omitted,
      Object? a3 = _omitted,
      Object? a4 = _omitted,
      Object? a5 = _omitted,
      Object? a6 = _omitted,
      Object? a7 = _omitted,
    ]) =>
        fn([a0, a1, a2, a3, a4, a5, a6, a7]
            .takeWhile((a) => !identical(a, _omitted))
            .toList());
  }

  /// Invokes export [name] with positional [args], applying ABI translation.
  ///
  /// The arguments are checked against the WIT signature first (SPEC 4.0.0
  /// §4): a wrong count, or a value outside its type's domain, throws an
  /// [ArgumentError] naming the export and the parameter. Nothing is coerced.
  /// `s64` takes an `int` or a `BigInt` and returns a `BigInt`.
  dynamic call(String name, [List<dynamic> args = const []]) {
    final fn = _fns[name];
    if (fn == null) {
      throw ArgumentError('export "$name" not found');
    }
    return fn(args);
  }
}

/// Builds a [ModuleExports] handle over [rawExports] using the Canonical ABI.
///
/// A WIT export the module does not export throws a [StateError] here, at
/// load time, naming it (SPEC 4.0.0 §2); so does a `string` signature on a
/// module without `memory` (or, for a `string` parameter, `cabi_realloc`).
ModuleExports buildComponentExportProxy(
  List<WitFunc> exportFuncs,
  JSObject rawExports,
) {
  const enc = Utf8Encoder();
  const dec = Utf8Decoder();

  final absent = exportFuncs.where((fn) {
    final f = getExport(rawExports, fn.tsName);
    return f == null || !f.isA<JSFunction>();
  });
  if (absent.isNotEmpty) {
    throw StateError('wasmImport: the .wit declares '
        'export${absent.length > 1 ? 's' : ''} the module does not export: '
        '${_names(absent)}');
  }

  final memJs = getExport(rawExports, 'memory');
  final memory = memJs == null ? null : memJs as WasmMemory;
  final reallocJs = getExport(rawExports, 'cabi_realloc');
  final cabiRealloc = reallocJs == null ? null : reallocJs as JSFunction;

  final usesStrings = exportFuncs.where((fn) =>
      fn.result == 'string' || fn.params.any((p) => p.type == 'string'));
  if (usesStrings.isNotEmpty && memory == null) {
    throw StateError('wasmImport: the module exports no `memory`, which the '
        'string export(s) need: ${_names(usesStrings)}');
  }
  final stringParams =
      exportFuncs.where((fn) => fn.params.any((p) => p.type == 'string'));
  if (stringParams.isNotEmpty && cabiRealloc == null) {
    throw StateError('wasmImport: the module exports no `cabi_realloc`, which '
        'the string parameter(s) need: ${_names(stringParams)}');
  }

  final fns = <String, Object? Function(List<Object?>)>{};

  for (final fn in exportFuncs) {
    final wasmFn = getExport(rawExports, fn.tsName) as JSFunction;
    final postJs = getExport(rawExports, 'cabi_post_${fn.tsName}');
    final post = postJs == null ? null : postJs as JSFunction;
    final n = fn.params.length;

    fns[fn.tsName] = (List<Object?> args) {
      if (args.length != n) {
        throw ArgumentError('wasmImport: ${_signature(fn)} expects $n '
            'argument${n == 1 ? '' : 's'}, got ${args.length}');
      }
      for (var i = 0; i < n; i++) {
        final p = fn.params[i];
        final expected = _domainProblem(p.type, args[i]);
        if (expected != null) {
          throw ArgumentError('wasmImport: ${_signature(fn)}: parameter '
              '${p.name} (${p.type}) expects $expected, got '
              '${_show(args[i])}');
        }
      }

      final wasmArgs = <JSAny?>[];
      for (var i = 0; i < n; i++) {
        final p = fn.params[i];
        final v = args[i]!;
        if (p.type == 'string') {
          final bytes = enc.convert(v as String);
          final ptr = (cabiRealloc!.callAsFunction(
                  null, 0.toJS, 0.toJS, 1.toJS, bytes.length.toJS) as JSNumber)
              .toDartInt;
          memoryBytes(memory!).setRange(ptr, ptr + bytes.length, bytes);
          wasmArgs.add(ptr.toJS);
          wasmArgs.add(bytes.length.toJS);
        } else {
          wasmArgs.add(_encodeScalar(p.type, v));
        }
      }

      final result = fn.result;
      if (result == 'string') {
        // Canonical ABI callee-allocated return: the export returns an i32
        // pointer to a callee-allocated [ptr, len] pair. Read it, decode (which
        // copies the bytes), then call cabi_post_<name> to release the buffer.
        final retArea = (_invoke(wasmFn, wasmArgs) as JSNumber).toDartInt;
        final retPtr = readI32(memory!, retArea);
        final retLen = readI32(memory, retArea + 4);
        final bytes = memoryBytes(memory);
        final str = dec.convert(
            Uint8List.fromList(bytes.sublist(retPtr, retPtr + retLen)));
        if (post != null) {
          post.callAsFunction(null, retArea.toJS);
        }
        return str;
      }

      final raw = _invoke(wasmFn, wasmArgs);
      if (result == null) return null;
      return _decodeScalar(result, raw);
    };
  }

  return ModuleExports._(fns, rawExports);
}

/// Calls [fn] with an arbitrary number of positional arguments via
/// `Function.prototype.apply` (`callAsFunction` is fixed-arity at 4).
@JS('Function.prototype.apply.call')
external JSAny? _applyJs(JSFunction fn, JSAny? thisArg, JSArray<JSAny?> args);

JSAny? _invoke(JSFunction fn, List<JSAny?> args) =>
    _applyJs(fn, null, args.toJS);
