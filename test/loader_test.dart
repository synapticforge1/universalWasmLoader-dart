@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:test/test.dart';
import 'package:universal_wasm_loader/universal_wasm_loader.dart';

// Fixtures live in test/fixtures/ and are served relative to this test file by
// the `dart test -p chrome` http server.
const _math = 'fixtures/math_50.wasm';
const _booleans = 'fixtures/booleans_50.wasm';
const _strings = 'fixtures/strings_50.wasm';
const _imports = 'fixtures/imports_50.wasm';
const _initCheck = 'fixtures/init_check.wasm';
const _wasiIo = 'fixtures/wasi_io_50.wasm';

void main() {
  group('math_50 — numeric round-trip', () {
    test('add / multiply / square', () async {
      final m = await wasmImport(_math);
      expect(m.call('add', [3, 4]), 7);
      expect(m.call('multiply', [2.5, 4.0]), 10.0);
      expect(m.call('square', [5]), 25);
    });
  });

  group('booleans_50 — bool normalization', () {
    test('isPositive / inRange / isEven', () async {
      final m = await wasmImport(_booleans);
      expect(m.call('isPositive', [1.0]), isTrue);
      expect(m.call('isPositive', [-1.0]), isFalse);
      expect(m.call('inRange', [5.0, 0.0, 10.0]), isTrue);
      expect(m.call('inRange', [11.0, 0.0, 10.0]), isFalse);
      expect(m.call('isEven', [4]), isTrue);
      expect(m.call('isEven', [3]), isFalse);
    });
  });

  group('strings_50 — string param + return (Canonical ABI)', () {
    test('greet / shout / strLen', () async {
      final m = await wasmImport(_strings);
      expect(m.call('greet', ['World']), 'Hello, World!');
      expect(m.call('shout', ['hi']), 'hihi');
      expect(m.call('strLen', ['hello']), 5);
    });
  });

  group('imports_50 — host import callbacks', () {
    test('scale / combine', () async {
      final m = await wasmImport(_imports, hostCallbacks: {
        'envMul': (num a, num b) => a * b,
        'envAdd': (num a, num b) => a + b,
      });
      expect(m.call('scale', [3.0, 4.0]), 12.0);
      expect(m.call('combine', [10, 7]), 17);
    });
  });

  group('instance lifecycle', () {
    test('createSingleton returns the same instance', () async {
      final getMod = createSingleton(_math);
      final a = await getMod();
      final b = await getMod();
      expect(identical(a, b), isTrue);
      expect(a.call('add', [1, 2]), 3);
    });

    test('InstancePool.run returns the correct result', () async {
      final pool = InstancePool(_math, size: 2);
      final result = await pool.run((mod) => mod.call('square', [6]));
      expect(result, 36);
    });

    test('InstancePool with size=2 handles 2 concurrent run() calls', () async {
      final pool = InstancePool(_math, size: 2);
      final results = await Future.wait([
        pool.run((mod) => mod.call('add', [10, 1]) as int),
        pool.run((mod) => mod.call('add', [20, 2]) as int),
      ]);
      expect(results, containsAll([11, 22]));
    });
  });

  group('SPEC §10 — producer model (loader capabilities)', () {
    test('§10.1 _initialize is called (no-WIT raw path)', () async {
      // init_check.wasm has no companion .wit; its `_initialize` sets a global
      // to 99 that `getValue` reads — 99 proves the loader invoked it. The raw
      // (no-WIT) branch still attaches the shim and calls _initialize.
      final m = await wasmImport(_initCheck);
      final getValue = m.rawExports.getProperty('getValue'.toJS) as JSFunction;
      final value = (getValue.callAsFunction() as JSNumber).toDartInt;
      expect(value, 99);
    });

    test('§10.2 a WASI-using library module instantiates and runs', () async {
      // wasi_io_50 is a modc library that calls console.log → imports fd_write;
      // it only instantiates because the loader supplies the WASI-P1 shim.
      final m = await wasmImport(_wasiIo);
      expect(m.call('logAndDouble', [21]), 42);
    });
  });
}
