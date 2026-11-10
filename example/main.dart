// Loads three WebAssembly modules in the browser and calls them through their
// companion `.wit` interfaces.
//
// This package is web-only. Put `math_50.wasm` / `.wit`, `strings_50.wasm` /
// `.wit` and `imports_50.wasm` / `.wit` (the reference fixtures, in this
// repository's `test/fixtures/`) next to the page that loads this script, then
// compile and serve it, for example:
//
//   dart compile js example/main.dart -o web/main.dart.js
//
// and open a page with `<script defer src="main.dart.js"></script>`.
import 'dart:async';

import 'package:universal_wasm_loader/universal_wasm_loader.dart';

Future<void> main() async {
  // 1. Numbers: the `.wit` beside `math_50.wasm` gives typed calls.
  final math = await wasmImport('math_50.wasm');
  print(math.call('add', [3, 4])); // 7
  print(math.call('multiply', [2.5, 4.0])); // 10.0

  // Arguments are checked against the WIT signature, never coerced.
  try {
    math.call('add', ['3', 4]);
  } on ArgumentError catch (e) {
    print('refused: ${e.message}');
  }

  // 2. Strings cross through the Canonical ABI (cabi_realloc / cabi_post_*).
  final strings = await wasmImport('strings_50.wasm');
  print(strings.call('greet', ['World'])); // Hello, World!

  // 3. Host callbacks: one for every WIT import, keyed by camelCase name.
  final imports = await wasmImport(
    'imports_50.wasm',
    hostCallbacks: {
      'envMul': (num a, num b) => a * b,
      'envAdd': (num a, num b) => a + b,
    },
    // A 5 s limit on each fetch instead of the default 30 s.
    options: const LoadOptions(timeout: Duration(seconds: 5)),
  );
  print(imports.call('scale', [3.0, 4.0])); // 12.0

  // 4. Many instances for concurrent work.
  final pool = InstancePool('math_50.wasm', size: 2);
  print(await pool.run((m) => m.call('square', [6]))); // 36

  // 5. A load can be cancelled.
  final token = LoadCancelToken();
  final pending =
      wasmImport('math_50.wasm', options: LoadOptions(cancel: token));
  token.cancel('no longer needed');
  try {
    await pending;
  } on Object catch (reason) {
    print('cancelled: $reason');
  }
}
