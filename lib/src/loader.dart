/// The public loader API: [wasmImport], [createSingleton], and [InstancePool].
///
/// Web platform only — uses the browser's native `WebAssembly` and `fetch` via
/// `dart:js_interop`.
library;

import 'dart:async';
import 'dart:js_interop';

import 'abi.dart';
import 'wasi.dart';
import 'wasm_interop.dart';
import 'wit_parser.dart';

class _VersionSuffix {
  final String cleanPath;
  final int? requestedVersion;
  const _VersionSuffix(this.cleanPath, this.requestedVersion);
}

_VersionSuffix _parseVersionSuffix(String wasmPath) {
  final atIdx = wasmPath.lastIndexOf('@');
  if (atIdx != -1) {
    final suffix = wasmPath.substring(atIdx + 1);
    if (RegExp(r'^\d+$').hasMatch(suffix)) {
      return _VersionSuffix(wasmPath.substring(0, atIdx), int.parse(suffix));
    }
  }
  return _VersionSuffix(wasmPath, null);
}

void _assertVersion(
    JSObject rawExports, int requestedVersion, String wasmPath) {
  final versionJs = getExport(rawExports, 'version');
  final global = versionJs == null ? null : versionJs as WasmGlobal;
  final value = global?.value;
  if (global == null || value == null || !value.isA<JSNumber>()) {
    throw StateError(
        'wasmImport: version @$requestedVersion requested for "$wasmPath" but '
        'the module does not export a "version" global');
  }
  final actual = (value as JSNumber).toDartInt;
  if (actual != requestedVersion) {
    throw StateError('wasmImport: version mismatch for "$wasmPath" — requested '
        '@$requestedVersion, module exports version $actual');
  }
}

/// Cancels a load started with [LoadOptions.cancel] (SPEC 4.0.0 §11).
///
/// Calling [cancel] aborts the fetch in progress; the load then fails with
/// [reason]. A token that is already cancelled fails a load before any fetch.
/// One token may serve several loads.
final class LoadCancelToken {
  /// A token that is not cancelled yet.
  LoadCancelToken();

  bool _cancelled = false;
  Object? _reason;
  final List<void Function()> _listeners = [];

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled;

  /// What a cancelled load throws: the value given to [cancel], or a
  /// [StateError] when none was.
  Object? get reason => _reason;

  /// Cancels every load holding this token. Later calls do nothing.
  void cancel([Object? reason]) {
    if (_cancelled) return;
    _cancelled = true;
    _reason = reason ?? StateError('wasmImport: the load was cancelled');
    for (final l in List.of(_listeners)) {
      l();
    }
    _listeners.clear();
  }

  void Function() _listen(void Function() onCancel) {
    _listeners.add(onCancel);
    return () => _listeners.remove(onCancel);
  }
}

/// Options for a load (SPEC 4.0.0 §1, §11).
final class LoadOptions {
  /// The default time limit for each http(s) fetch: 30 seconds.
  static const defaultTimeout = Duration(seconds: 30);

  /// The time limit for each fetch (the `.wit`, then the `.wasm`), from the
  /// request to the last byte of the body. `null` means no limit. Zero or
  /// negative is refused when a load starts.
  final Duration? timeout;

  /// Cancels the load; see [LoadCancelToken].
  final LoadCancelToken? cancel;

  /// Options with a [timeout] per fetch (default 30 s; `null` for no limit)
  /// and an optional [cancel] token.
  const LoadOptions({this.timeout = defaultTimeout, this.cancel});
}

void _checkOptions(LoadOptions o) {
  final t = o.timeout;
  if (t != null && t <= Duration.zero) {
    throw ArgumentError.value(t, 'options.timeout',
        'wasmImport: must be a positive Duration, or null for no limit');
  }
  final c = o.cancel;
  if (c != null && c.isCancelled) throw c.reason!;
}

/// Fetches [url] once and hands the response to [use], all under ONE time
/// limit (request to the last byte of the body) and the caller's cancel token.
/// A timeout, a cancellation and a network error each become an error naming
/// the URL; an error thrown by [use] otherwise reaches the caller as it is.
Future<T> _fetchOnce<T>(
  Uri url,
  LoadOptions o,
  Future<T> Function(FetchResponse res) use,
) async {
  final ctl = AbortController();
  var timedOut = false;
  final limit = o.timeout;
  final timer = limit == null
      ? null
      : Timer(limit, () {
          timedOut = true;
          ctl.abort();
        });
  final unlisten = o.cancel?._listen(() => ctl.abort());
  Object? why() {
    final c = o.cancel;
    if (c != null && c.isCancelled) return c.reason;
    if (timedOut) {
      return TimeoutException(
          'wasmImport: timed out after ${limit!.inMilliseconds} ms fetching '
          '$url',
          limit);
    }
    return null;
  }

  try {
    final init = JSObject();
    jsSet(init, 'signal'.toJS, ctl.signal);
    final FetchResponse res;
    try {
      res = await fetch(url.toString().toJS, init).toDart;
    } catch (e) {
      throw why() ?? StateError('wasmImport: could not fetch $url: $e');
    }
    try {
      return await use(res);
    } catch (_) {
      final w = why();
      if (w != null) throw w;
      rethrow;
    }
  } finally {
    timer?.cancel();
    unlisten?.call();
  }
}

/// Fetches the `.wasm` (one request; an HTTP error names the status and URL),
/// then instantiates it; a compile or link error reaches the caller as it is.
Future<JSObject> _instantiate(Uri url, JSObject imports, LoadOptions o) async {
  final buffer = await _fetchOnce(url, o, (res) async {
    if (!res.ok) {
      throw StateError('wasmImport: HTTP ${res.status} for $url');
    }
    return res.arrayBuffer().toDart;
  });
  final source = await WebAssembly.instantiate(buffer, imports).toDart;
  return source.instance.exports;
}

/// The companion `.wit` URL: the `.wasm` path's suffix replaced, query and
/// fragment dropped (SPEC §2). `null` when the path does not end in `.wasm`.
Uri? _witUrlFor(Uri wasmUrl) {
  final path = wasmUrl.path;
  if (!path.toLowerCase().endsWith('.wasm')) return null;
  return Uri(
    scheme: wasmUrl.scheme,
    userInfo: wasmUrl.userInfo,
    host: wasmUrl.host,
    port: wasmUrl.hasPort ? wasmUrl.port : null,
    path: '${path.substring(0, path.length - 5)}.wit',
  );
}

/// Reads the companion `.wit` (SPEC 4.0.0 §2). `null` ONLY when it is absent —
/// HTTP 404 or 410 — which selects raw exports. Every other failure throws:
/// another HTTP status, a network error, the time limit, cancellation.
Future<String?> _readWit(Uri? witUrl, LoadOptions o) async {
  if (witUrl == null) return null;
  return _fetchOnce(witUrl, o, (res) async {
    if (res.status == 404 || res.status == 410) return null;
    if (!res.ok) {
      throw StateError('wasmImport: HTTP ${res.status} for $witUrl');
    }
    return (await res.text().toDart).toDart;
  });
}

/// SPEC §10.1 — invoke a reactor module's `_initialize` export once after
/// instantiation, before any other export is used. No-op if not exported.
void _callInitialize(JSObject rawExports) {
  final initJs = getExport(rawExports, '_initialize');
  if (initJs != null && initJs.isA<JSFunction>()) {
    (initJs as JSFunction).callAsFunction();
  }
}

/// Instantiates the `.wasm` at [wasmPath], returning a typed [ModuleExports]
/// handle.
///
/// Auto-detects the companion `.wit` (replace `.wasm` -> `.wit`, fetch) and
/// applies the Canonical ABI. Only an ABSENT `.wit` (HTTP 404 or 410, or a
/// path not ending in `.wasm`) gives raw exports, wrapped with no translation;
/// any other `.wit` failure, and a `.wit` that does not parse (a
/// [FormatException]), fails the load before the `.wasm` is fetched
/// (SPEC 4.0.0 §2). An optional `@N` suffix pins to the module's exported
/// `version` global (see SPEC §3).
///
/// [hostCallbacks] supplies host import functions keyed by camelCase WIT name
/// (e.g. `envMul`): one for EVERY WIT import, or the load fails with an
/// [ArgumentError] naming the missing ones. Each callback's return value must
/// match the import's WIT result (an `int` for `s32`, a `num` for `f64`, a
/// `bool` for `bool`, never a `Future`); a wrong one throws an [ArgumentError]
/// to the caller of the export that called it (SPEC 4.0.0 §4).
///
/// [options] sets the time limit on each fetch (default 30 s; a
/// [TimeoutException] names the URL) and a [LoadCancelToken] (SPEC §11).
///
/// SPEC §10 (producer model): a minimal WASI Preview 1 shim is always supplied
/// so an I/O-using library module (e.g. a `modc` library that calls
/// `console.log` → `fd_write`) instantiates on the web, which has no native
/// WASI; unused import namespaces are ignored by `WebAssembly.instantiate`, so
/// pure-compute modules are unaffected. A reactor module's `_initialize` export
/// is invoked once after instantiation.
Future<ModuleExports> wasmImport(
  String wasmPath, {
  Map<String, Function> hostCallbacks = const {},
  LoadOptions options = const LoadOptions(),
}) async {
  _checkOptions(options);
  final parsed = _parseVersionSuffix(wasmPath);
  final cleanPath = parsed.cleanPath;
  final requestedVersion = parsed.requestedVersion;
  final wasmUrl = Uri.base.resolve(cleanPath);

  // WIT auto-detection: absent → raw exports; any other failure throws (SPEC §2).
  final witUrl = _witUrlFor(wasmUrl);
  final witSrc = await _readWit(witUrl, options);

  // SPEC §10.2 — always provide the minimal WASI-P1 shim.
  final wasiMemRef = WasiMemRef();
  final wasi = buildWasiShim(wasiMemRef);

  if (witSrc == null) {
    final imports = JSObject();
    jsSet(imports, 'wasi_snapshot_preview1'.toJS, wasi);
    final rawExports = await _instantiate(wasmUrl, imports, options);
    final memJs = getExport(rawExports, 'memory');
    if (memJs != null) {
      wasiMemRef.current = memJs as WasmMemory;
    }
    _callInitialize(rawExports); // SPEC §10.1
    if (requestedVersion != null) {
      _assertVersion(rawExports, requestedVersion, cleanPath);
    }
    // No WIT: expose raw exports with no ABI translation (empty func table).
    return buildComponentExportProxy(const [], rawExports);
  }

  final ParsedWit parsedWit;
  try {
    parsedWit = parseWit(witSrc);
  } on FormatException catch (e) {
    throw FormatException('wasmImport: invalid .wit $witUrl: ${e.message}');
  }
  // Refuses missing callbacks and string-result imports, before the fetch.
  final importEnv = buildComponentImportEnv(parsedWit.imports, hostCallbacks);

  final imports = JSObject();
  jsSet(imports, 'wasi_snapshot_preview1'.toJS, wasi);
  if (parsedWit.imports.isNotEmpty) {
    jsSet(imports, 'env'.toJS, importEnv.env);
  }

  final rawExports = await _instantiate(wasmUrl, imports, options);
  final memJs = getExport(rawExports, 'memory');
  if (memJs != null) {
    final mem = memJs as WasmMemory;
    importEnv.memRef.current = mem; // for env string-param decoding
    wasiMemRef.current = mem; // for the WASI shim
  }
  _callInitialize(rawExports); // SPEC §10.1
  if (requestedVersion != null) {
    _assertVersion(rawExports, requestedVersion, cleanPath);
  }
  return buildComponentExportProxy(parsedWit.exports, rawExports);
}

/// Creates a singleton accessor that loads the WASM instance on the first call
/// and caches the load. Subsequent calls return the same future/instance.
///
/// Appropriate for CLI tools and bounded-call scenarios (SPEC §6.1). [options]
/// apply to the load (SPEC §11.4).
Future<ModuleExports> Function() createSingleton(
  String wasmPath, {
  Map<String, Function> hostCallbacks = const {},
  LoadOptions options = const LoadOptions(),
}) {
  Future<ModuleExports>? cached;
  return () {
    cached ??=
        wasmImport(wasmPath, hostCallbacks: hostCallbacks, options: options);
    return cached!;
  };
}

/// A pool of pre-instantiated WASM instances for concurrent or high-throughput
/// scenarios (SPEC §6.2).
///
/// Manages acquire/release semantics so no two concurrent callers share the
/// same instance. Use [run] for an atomic checkout-call-release pattern.
class InstancePool {
  final String _wasmPath;
  final Map<String, Function> _hostCallbacks;
  final int _size;
  final LoadOptions _options;

  Future<void>? _initFuture;
  final List<ModuleExports> _available = [];
  final List<Completer<ModuleExports>> _waiters = [];

  /// Creates a pool of [size] (default 4) independent instances of the module
  /// at [wasmPath]. Instances are lazily created on first [acquire]/[run];
  /// [options] apply to each instance's load (SPEC §11.4).
  InstancePool(
    this._wasmPath, {
    Map<String, Function> hostCallbacks = const {},
    int size = 4,
    LoadOptions options = const LoadOptions(),
  })  : _hostCallbacks = hostCallbacks,
        _size = size,
        _options = options;

  /// Total pool capacity.
  int get size => _size;

  /// The number of currently-idle instances.
  int get available => _available.length;

  Future<void> _ensureInit() {
    return _initFuture ??= Future(() async {
      final instances = await Future.wait(List.generate(
        _size,
        (_) => wasmImport(_wasmPath,
            hostCallbacks: _hostCallbacks, options: _options),
      ));
      _available.addAll(instances);
    });
  }

  /// Acquires an available instance, waiting if all are in use.
  Future<ModuleExports> acquire() async {
    await _ensureInit();
    if (_available.isNotEmpty) {
      return _available.removeLast();
    }
    final completer = Completer<ModuleExports>();
    _waiters.add(completer);
    return completer.future;
  }

  /// Releases [instance] back to the pool, handing it to a waiter if present.
  void release(ModuleExports instance) {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(instance);
    } else {
      _available.add(instance);
    }
  }

  /// Atomically acquires an instance, runs [fn] with it, then releases it —
  /// even if [fn] throws.
  Future<T> run<T>(FutureOr<T> Function(ModuleExports instance) fn) async {
    final instance = await acquire();
    try {
      return await fn(instance);
    } finally {
      release(instance);
    }
  }
}
