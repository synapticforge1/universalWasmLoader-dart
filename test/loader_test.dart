@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:test/test.dart';
import 'package:universal_wasm_loader/universal_wasm_loader.dart';
import 'package:web/web.dart' as web;

// Fixtures live in test/fixtures/ and are served relative to this test file by
// the `dart test -p chrome` http server.
const _math = 'fixtures/math_50.wasm';
const _booleans = 'fixtures/booleans_50.wasm';
const _strings = 'fixtures/strings_50.wasm';
const _imports = 'fixtures/imports_50.wasm';
const _initCheck = 'fixtures/init_check.wasm';
const _wasiIo = 'fixtures/wasi_io_50.wasm';

Map<String, Function> _callbacks() => {
      'envMul': (num a, num b) => a * b,
      'envAdd': (num a, num b) => a + b,
    };

/// An error of type [T] whose `toString()` contains every one of [parts].
Matcher _fails<T>(List<String> parts) => throwsA(isA<T>()
    .having((e) => e.toString(), 'toString()', stringContainsInOrder(parts)));

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

  group('SPEC 4.0.0 §8 Refusals — host callbacks', () {
    test('imports_50 with no callbacks names both', () async {
      await expectLater(wasmImport(_imports),
          _fails<ArgumentError>(['envMul', 'env-mul', 'envAdd', 'env-add']));
    });

    test('imports_50 with only envMul names envAdd', () async {
      await expectLater(
          wasmImport(_imports, hostCallbacks: {
            'envMul': (num a, num b) => a * b,
          }),
          throwsA(isA<ArgumentError>().having((e) => e.toString(), 'message',
              allOf(contains('envAdd'), isNot(contains('envMul'))))));
    });

    final badReturns = <String, Object? Function()>{
      'null': () => null,
      '2.9': () => 2.9,
      '2^31': () => 2147483648,
      'true': () => true,
      '"17"': () => '17',
      'BigInt 17': () => BigInt.from(17),
    };
    for (final MapEntry(key: label, value: make) in badReturns.entries) {
      test('envAdd returning $label is refused when combine calls it',
          () async {
        final m = await wasmImport(_imports, hostCallbacks: {
          'envMul': (num a, num b) => a * b,
          'envAdd': (num a, num b) => make(),
        });
        expect(() => m.call('combine', [10, 7]),
            _fails<ArgumentError>(['envAdd', 'env-add', 's32', 'returned']));
      });
    }

    test('an async envMul is refused when scale calls it', () async {
      final m = await wasmImport(_imports, hostCallbacks: {
        'envMul': (num a, num b) async => a * b,
        'envAdd': (num a, num b) => a + b,
      });
      expect(() => m.call('scale', [3.0, 4.0]),
          _fails<ArgumentError>(['envMul', 'Future']));
    });
  });

  group('SPEC 4.0.0 §8 Refusals — typed-call arguments', () {
    late ModuleExports math, strings, booleans;
    setUpAll(() async {
      math = await wasmImport(_math);
      strings = await wasmImport(_strings);
      booleans = await wasmImport(_booleans);
    });

    test('add("x", 1) / add(2.7, 1) / add(1, 2^31) / add(null, 1)', () {
      for (final args in [
        ['x', 1],
        [2.7, 1],
        [null, 1],
      ]) {
        expect(() => math.call('add', args),
            _fails<ArgumentError>(['add', 'parameter a', 's32']));
      }
      expect(() => math.call('add', [1, 2147483648]),
          _fails<ArgumentError>(['add', 'parameter b', 's32']));
    });

    test('add(1) / add(1, 2, 3) name the count', () {
      expect(() => math.call('add', [1]),
          _fails<ArgumentError>(['add', 'expects 2 arguments, got 1']));
      expect(() => math.call('add', [1, 2, 3]),
          _fails<ArgumentError>(['add', 'expects 2 arguments, got 3']));
    });

    test('function() checks the same way', () {
      final add = math.function('add')!;
      expect(add(3, 4), 7);
      expect(() => add(1), _fails<ArgumentError>(['add', 'got 1']));
      expect(() => add(null, 1), _fails<ArgumentError>(['parameter a']));
    });

    test('greet(42) on strings_50; isEven("4") on booleans_50', () {
      expect(() => strings.call('greet', [42]),
          _fails<ArgumentError>(['greet', 'parameter', 'string']));
      expect(() => booleans.call('isEven', ['4']),
          _fails<ArgumentError>(['isEven', 'parameter', 's32']));
      expect(() => booleans.call('isPositive', [1]), returnsNormally);
    });
  });

  group('SPEC 4.0.0 §2 — strict .wit parsing', () {
    test('a missing comma, u32, an empty file, a duplicate, text outside', () {
      const head = 'package local:m;\nworld m {\n';
      for (final (src, fault) in [
        ('${head}export add: func(a: s32 b: s32) -> s32;\n}', 'malformed'),
        ('${head}export add: func(a: u32) -> s32;\n}', 'u32'),
        ('${head}export add: func() -> list<u8>;\n}', 'list<u8>'),
        ('', 'empty'),
        ('${head}export f: func();\nexport f: func();\n}', 'duplicate'),
        ('${head}export f: func(a: s32, a: s32);\n}', 'duplicate'),
        ('${head}export f: func();\n}\nworld n {}', 'world'),
        ('${head}type t = u8;\n}', 'statement'),
        ('${head}export f: func()\n}', 'missing ";"'),
      ]) {
        expect(() => parseWit(src), _fails<FormatException>([fault]),
            reason: src);
      }
    });

    test('the fixtures, comments and a trailing comma parse', () {
      final w = parseWit('// c\npackage a:b;\nworld b { // x\n'
          '  export f: func(a: s32,) -> bool;\n}\n');
      expect(w.exports.single.params.single.type, 's32');
      expect(w.exports.single.result, 'bool');
    });
  });

  group('SPEC 4.0.0 over http (§2, §11)', () {
    late String base;
    setUpAll(() async {
      final channel = spawnHybridUri('support/http_server.dart');
      final port = await channel.stream.first as int;
      base = 'http://127.0.0.1:$port';
    });

    Future<Map<String, Object?>> counts() async {
      final res = await web.window.fetch('$base/__counts'.toJS).toDart;
      final text = (await res.text().toDart).toDart;
      return jsonDecode(text) as Map<String, Object?>;
    }

    int rawAdd(ModuleExports m, int a, int b) =>
        (m.rawExports.callMethod<JSNumber>('add'.toJS, a.toJS, b.toJS))
            .toDartInt;

    test('a .wit answering 404 or 410 loads math_50 as raw exports', () async {
      for (final mode in ['wit404', 'wit410']) {
        final m = await wasmImport('$base/$mode/t/math_50.wasm');
        expect(m.names, isEmpty);
        expect(rawAdd(m, 3, 4), 7);
      }
    });

    test('a .wit answering 500 fails, naming the URL and status, once',
        () async {
      await expectLater(wasmImport('$base/wit500/t/math_50.wasm'),
          _fails<StateError>(['HTTP 500', '/wit500/t/math_50.wit']));
      final c = await counts();
      expect(c['/wit500/t/math_50.wit'], 1);
      expect(c['/wit500/t/math_50.wasm'], isNull,
          reason: 'the .wasm is never fetched');
    });

    test('a .wasm answering 404 or 500 fails, naming the URL and status, once',
        () async {
      await expectLater(wasmImport('$base/wasm404/t/math_50.wasm'),
          _fails<StateError>(['HTTP 404', '/wasm404/t/math_50.wasm']));
      await expectLater(wasmImport('$base/wasm500/t/math_50.wasm'),
          _fails<StateError>(['HTTP 500', '/wasm500/t/math_50.wasm']));
      final c = await counts();
      expect(c['/wasm404/t/math_50.wasm'], 1);
      expect(c['/wasm500/t/math_50.wasm'], 1);
    });

    test('a server that never answers hits the time limit (.wit, .wasm, body)',
        () async {
      const limit = LoadOptions(timeout: Duration(milliseconds: 300));
      for (final (mode, file) in [
        ('hangwit', 'math_50.wit'),
        ('hangwasm', 'math_50.wasm'),
        ('partial', 'math_50.wasm'),
      ]) {
        await expectLater(
            wasmImport('$base/$mode/t/math_50.wasm', options: limit),
            _fails<TimeoutException>(['300 ms', '/$mode/t/$file']));
      }
    });

    test('a parse fault or u32 names the .wit and the fault; no .wasm fetch',
        () async {
      await expectLater(wasmImport('$base/badwit/t/math_50.wasm'),
          _fails<FormatException>(['/badwit/t/math_50.wit', 'malformed']));
      await expectLater(wasmImport('$base/u32wit/t/math_50.wasm'),
          _fails<FormatException>(['/u32wit/t/math_50.wit', 'u32']));
      final c = await counts();
      expect(c['/badwit/t/math_50.wasm'], isNull);
      expect(c['/u32wit/t/math_50.wasm'], isNull);
    });

    test('an import with a string result fails before the .wasm is fetched',
        () async {
      await expectLater(
          wasmImport('$base/strimport/t/imports_50.wasm',
              hostCallbacks: _callbacks()),
          _fails<UnsupportedError>(['string', 'envMul', 'env-mul']));
      expect((await counts())['/strimport/t/imports_50.wasm'], isNull);
    });

    test('a missing callback fails before the .wasm is fetched', () async {
      await expectLater(wasmImport('$base/ok/t/imports_50.wasm'),
          _fails<ArgumentError>(['envMul', 'envAdd']));
      expect((await counts())['/ok/t/imports_50.wasm'], isNull);
    });

    test('a WIT export the module lacks fails the load, naming it', () async {
      await expectLater(wasmImport('$base/extraexport/t/math_50.wasm'),
          _fails<StateError>(['does not export', 'cube']));
    });

    test('the .wit URL drops the query; a non-.wasm path has no .wit',
        () async {
      final m = await wasmImport('$base/ok/q/math_50.wasm?v=1');
      expect(m.call('add', [3, 4]), 7);
      final raw = await wasmImport('$base/ok/b/math_50.bin');
      expect(raw.names, isEmpty);
      expect(rawAdd(raw, 3, 4), 7);
      final c = await counts();
      expect(c['/ok/q/math_50.wit'], 1);
      expect(
          c.keys.where((k) => k.startsWith('/ok/b/')), ['/ok/b/math_50.bin']);
    });

    test('cancellation: during a fetch, and before any fetch', () async {
      final token = LoadCancelToken();
      final load = wasmImport('$base/hangwit/c/math_50.wasm',
          options: LoadOptions(cancel: token));
      Timer(const Duration(milliseconds: 100), () => token.cancel('stop'));
      await expectLater(load, throwsA('stop'));

      await expectLater(
          wasmImport('$base/ok/c/math_50.wasm',
              options: LoadOptions(cancel: token)),
          throwsA('stop'));
      final fresh = LoadCancelToken()..cancel();
      await expectLater(
          wasmImport('$base/ok/c2/math_50.wasm',
              options: LoadOptions(cancel: fresh)),
          _fails<StateError>(['cancelled']));
      final c = await counts();
      expect(c.keys.where((k) => k.startsWith('/ok/c')), isEmpty);
    });

    test('options.timeout must be positive; null means no limit', () async {
      await expectLater(
          wasmImport(_math, options: const LoadOptions(timeout: Duration.zero)),
          throwsA(isA<ArgumentError>()));
      final m =
          await wasmImport(_math, options: const LoadOptions(timeout: null));
      expect(m.call('add', [3, 4]), 7);
    });

    test('createSingleton and InstancePool apply options', () async {
      const limit = LoadOptions(timeout: Duration(milliseconds: 200));
      await expectLater(
          createSingleton('$base/hangwit/s/math_50.wasm', options: limit)(),
          throwsA(isA<TimeoutException>()));
      await expectLater(
          InstancePool('$base/hangwit/p/math_50.wasm', size: 1, options: limit)
              .run((m) => m),
          throwsA(isA<TimeoutException>()));
    });

    test('s64 passes as a 64-bit integer and returns a BigInt', () async {
      final m = await wasmImport('$base/s64/t/add64.wasm');
      final max = BigInt.parse('9223372036854775807');
      expect(m.call('add64', [max - BigInt.one, BigInt.one]), max);
      expect(m.call('add64', [2, 3]), BigInt.from(5));
      expect(() => m.call('add64', [max + BigInt.one, BigInt.zero]),
          _fails<ArgumentError>(['add64', 'parameter a', 's64']));
      expect(() => m.call('add64', [1.5, 1]),
          _fails<ArgumentError>(['parameter a', 's64']));
    });
  });
}
