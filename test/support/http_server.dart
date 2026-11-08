// A test HTTP server for the SPEC 4.0.0 refusal cases (§2, §11), run in the
// Dart VM by `spawnHybridUri` beside the browser suite. Not a test file.
//
// URL form: /<mode>/<tag>/<file>. <mode> picks the behaviour; <tag> keeps each
// test's request counts apart; <file> names a fixture in test/fixtures/.
// GET /__counts returns {path: requests} as JSON.
import 'dart:convert';
import 'dart:io';

/// A hand-built module: `(func (export "add64") (param i64 i64) (result i64)
/// local.get 0 local.get 1 i64.add)` — no fixture uses s64.
const _add64Wasm = [
  0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, // magic, version
  0x01, 0x07, 0x01, 0x60, 0x02, 0x7e, 0x7e, 0x01, 0x7e, // type: (i64 i64)->i64
  0x03, 0x02, 0x01, 0x00, // function: type 0
  0x07, 0x09, 0x01, 0x05, 0x61, 0x64, 0x64, 0x36, 0x34, 0x00, 0x00, // "add64"
  0x0a, 0x09, 0x01, 0x07, 0x00, 0x20, 0x00, 0x20, 0x01, 0x7c, 0x0b, // body
];

const _add64Wit = 'package local:s64;\n'
    'world s64 {\n'
    '  export add64: func(a: s64, b: s64) -> s64;\n'
    '}\n';

/// `.wit` sources served beside a fixture `.wasm` for the parse and
/// load-time refusals.
const _witFor = {
  // A missing comma: "b" has no separator.
  'badwit': 'package local:math-50;\n'
      'world math-50 {\n'
      '  export add: func(a: s32 b: s32) -> s32;\n'
      '}\n',
  'u32wit': 'package local:math-50;\n'
      'world math-50 {\n'
      '  export add: func(a: u32, b: u32) -> u32;\n'
      '}\n',
  'strimport': 'package local:imports-50;\n'
      'world imports-50 {\n'
      '  import env-mul: func(p0: f64, p1: f64) -> string;\n'
      '  import env-add: func(p0: s32, p1: s32) -> s32;\n'
      '  export scale: func(x: f64, factor: f64) -> f64;\n'
      '  export combine: func(a: s32, b: s32) -> s32;\n'
      '}\n',
  'extraexport': 'package local:math-50;\n'
      'world math-50 {\n'
      '  export add: func(a: s32, b: s32) -> s32;\n'
      '  export cube: func(x: s32) -> s32;\n'
      '}\n',
};

/// What each mode does with the `.wit` and the `.wasm` request: `file`
/// serves the fixture, a number answers that status, `hang` never answers,
/// `partial` sends the headers and half the body and then stalls.
const _modes = {
  'ok': ('file', 'file'),
  'wit404': (404, 'file'),
  'wit410': (410, 'file'),
  'wit500': (500, 'file'),
  'wasm404': (404, 404),
  'wasm500': ('file', 500),
  'hangwit': ('hang', 'file'),
  'hangwasm': (404, 'hang'),
  'partial': (404, 'partial'),
  'badwit': ('custom', 'file'),
  'u32wit': ('custom', 'file'),
  'strimport': ('custom', 'file'),
  'extraexport': ('custom', 'file'),
  's64': ('custom', 'custom'),
};

Future<void> hybridMain(dynamic channel) async {
  final counts = <String, int>{};
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final res = req.response;
    res.headers.set('Access-Control-Allow-Origin', '*');
    final path = req.uri.path;
    if (path == '/__counts') {
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(counts));
      await res.close();
      return;
    }
    counts[path] = (counts[path] ?? 0) + 1;

    final segs = req.uri.pathSegments;
    final mode = segs.isEmpty ? '' : segs.first;
    final file = segs.isEmpty ? '' : segs.last;
    final behaviour = _modes[mode];
    if (behaviour == null || segs.length != 3) {
      res.statusCode = 400;
      await res.close();
      return;
    }
    final isWit = file.endsWith('.wit');
    final action = isWit ? behaviour.$1 : behaviour.$2;

    if (action is int) {
      res.statusCode = action;
      res.write('status $action');
      await res.close();
      return;
    }
    switch (action) {
      case 'hang':
        return; // never answered
      case 'custom':
        if (mode == 's64') {
          if (isWit) {
            res.write(_add64Wit);
          } else {
            res.headers.contentType = ContentType('application', 'wasm');
            res.add(_add64Wasm);
          }
        } else {
          res.write(_witFor[mode]!);
        }
        await res.close();
        return;
    }
    // 'file' or 'partial': a fixture; `.bin` serves the `.wasm` bytes under a
    // name with no companion `.wit`.
    final name = file.endsWith('.bin')
        ? '${file.substring(0, file.length - 4)}.wasm'
        : file;
    final f = File('test/fixtures/$name');
    if (!f.existsSync()) {
      res.statusCode = 404;
      await res.close();
      return;
    }
    final bytes = f.readAsBytesSync();
    if (action == 'partial') {
      res.contentLength = bytes.length;
      res.add(bytes.sublist(0, bytes.length ~/ 2));
      await res.flush();
      return; // the rest never comes
    }
    res.add(bytes);
    await res.close();
  });
  channel.sink.add(server.port);
}
