// Tests for scripts/ci_release.dart (workspace H30, C34, H32) against an
// in-process mock of GitHub's REST API and pub.dev. The script runs as a child
// process (Process.run is asynchronous, so the mock keeps serving), exactly as
// CI runs it. Run: dart test -p vm test/ci_release_test.dart
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _c = 'cccccccccccccccccccccccccccccccccccccccc';
const _other = '0000000000000000000000000000000000000000';

/// What the mock answers; every request is logged in [log].
class _Mock {
  String tag = 'commit'; // commit | annotated | missing | other
  bool moveTagAfterPost = false;
  bool releaseExists = false;
  int postStatus = 201;
  bool readBackDraft = false;
  bool stall = false;
  int pubStatus = 404;
  final log = <String>[];
  bool _posted = false;

  late HttpServer _server;
  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final body = await utf8.decoder.bind(req).join();
    final auth = req.headers.value('authorization') == null ? '' : ' auth';
    log.add(
        '${req.method} ${req.uri.path}$auth${body.isEmpty ? '' : ' $body'}');
    if (stall) return; // never answered
    final p = req.uri.path;
    final res = req.response..headers.contentType = ContentType.json;
    void send(int s, [Object o = const {}]) {
      res.statusCode = s;
      res.write(jsonEncode(o));
    }

    if (p.startsWith('/api/packages/')) {
      send(pubStatus);
    } else if (p.endsWith('/git/ref/tags/v1.0.0')) {
      final moved = moveTagAfterPost && _posted;
      switch (moved ? 'other' : tag) {
        case 'missing':
          send(404);
        case 'annotated':
          send(200, {
            'object': {'type': 'tag', 'sha': 'ttt'}
          });
        case 'other':
          send(200, {
            'object': {'type': 'commit', 'sha': _other}
          });
        default:
          send(200, {
            'object': {'type': 'commit', 'sha': _c}
          });
      }
    } else if (p.endsWith('/git/tags/ttt')) {
      send(200, {
        'object': {'type': 'commit', 'sha': _c}
      });
    } else if (p.endsWith('/releases/tags/v1.0.0')) {
      if (releaseExists || _posted) {
        send(200, {
          'tag_name': 'v1.0.0',
          'draft': readBackDraft,
          'html_url': 'https://example.invalid/r'
        });
      } else {
        send(404);
      }
    } else if (p.endsWith('/releases') && req.method == 'POST') {
      if (postStatus == 201) _posted = true;
      send(postStatus);
    } else {
      send(404);
    }
    await res.close();
  }

  int get posts => log.where((l) => l.startsWith('POST')).length;
}

Future<ProcessResult> _run(_Mock m, List<String> args,
    {String? token = 'test-token', String ref = 'v1.0.0'}) {
  // The parent environment minus everything the script reads: an EMPTY
  // environment breaks sockets on Windows (Winsock needs SystemRoot).
  final base = Map.of(Platform.environment)
    ..removeWhere((k, _) =>
        k.toUpperCase().startsWith('GITHUB_') ||
        k.toUpperCase() == 'PUB_API_URL' ||
        k.toUpperCase() == 'CI_HTTP_TIMEOUT_MS');
  return Process.run(
    Platform.resolvedExecutable,
    ['run', 'scripts/ci_release.dart', ...args],
    environment: {
      ...base,
      'GITHUB_API_URL': m.url,
      'PUB_API_URL': m.url,
      'GITHUB_REPOSITORY': 'o/r',
      'GITHUB_REF_NAME': ref,
      'GITHUB_SHA': _c,
      if (token != null) 'GITHUB_TOKEN': token,
      'CI_HTTP_TIMEOUT_MS': '1500',
    },
    includeParentEnvironment: false,
  );
}

String _out(ProcessResult r) => '${r.stdout}${r.stderr}';

void main() {
  late _Mock m;
  setUp(() async {
    m = _Mock();
    await m.start();
  });
  tearDown(() => m.stop());

  group('github-release', () {
    test('lightweight tag: POST once (token, notes, pub.dev link), read back',
        () async {
      final r = await _run(m, ['github-release']);
      expect(r.exitCode, 0, reason: _out(r));
      expect(m.posts, 1);
      final post = m.log.singleWhere((l) => l.startsWith('POST'));
      expect(post, contains(' auth'));
      expect(post, contains('"generate_release_notes":true'));
      expect(
          post,
          contains(
              'https://pub.dev/packages/universal_wasm_loader/versions/1.0.0'));
      expect(_out(r), contains('after the POST'));
    });

    test('annotated tag is peeled to its commit', () async {
      m.tag = 'annotated';
      final r = await _run(m, ['github-release']);
      expect(r.exitCode, 0, reason: _out(r));
      expect(m.log, contains('GET /repos/o/r/git/tags/ttt auth'));
      expect(m.posts, 1);
    });

    test('a missing tag is refused with no POST', () async {
      m.tag = 'missing';
      final r = await _run(m, ['github-release']);
      expect(r.exitCode, 1);
      expect(_out(r), contains('does not exist'));
      expect(m.posts, 0);
    });

    test('a tag at another commit is refused with no POST', () async {
      m.tag = 'other';
      final r = await _run(m, ['github-release']);
      expect(r.exitCode, 1);
      expect(_out(r), contains('not this run\'s commit'));
      expect(m.posts, 0);
    });

    test('an existing release is done: exit 0, no POST', () async {
      m.releaseExists = true;
      final r = await _run(m, ['github-release']);
      expect(r.exitCode, 0, reason: _out(r));
      expect(_out(r), contains('already exists'));
      expect(m.posts, 0);
    });

    test('a refused POST (422) fails', () async {
      m.postStatus = 422;
      final r = await _run(m, ['github-release']);
      expect(r.exitCode, 1);
      expect(_out(r), contains('422'));
    });

    test('a draft on read-back fails', () async {
      m.readBackDraft = true;
      final r = await _run(m, ['github-release']);
      expect(r.exitCode, 1);
      expect(_out(r), contains('read-back'));
    });

    test('a tag moved after the POST fails', () async {
      m.moveTagAfterPost = true;
      final r = await _run(m, ['github-release']);
      expect(r.exitCode, 1);
      expect(_out(r), contains('after the POST'));
      expect(m.posts, 1);
    });

    test('--dry-run sends no POST', () async {
      final r = await _run(m, ['github-release', '--dry-run']);
      expect(r.exitCode, 0, reason: _out(r));
      expect(_out(r), contains('dry run'));
      expect(m.posts, 0);
    });

    test('no token: refused before any request', () async {
      final r = await _run(m, ['github-release'], token: null);
      expect(r.exitCode, 1);
      expect(_out(r), contains('GITHUB_TOKEN'));
      expect(m.log, isEmpty);
    });

    test('a stalled API fails at the time limit, not hangs', () async {
      m.stall = true;
      final sw = Stopwatch()..start();
      final r = await _run(m, ['github-release']);
      expect(r.exitCode, 1);
      expect(_out(r), contains('timed out after 1500 ms'));
      expect(sw.elapsed, lessThan(const Duration(seconds: 20)));
      expect(m.posts, 0);
    });
  });

  group('pub-has', () {
    late String pubspec;
    setUp(() {
      final dir = Directory.systemTemp.createTempSync('ci_release_test');
      pubspec = '${dir.path}${Platform.pathSeparator}pubspec.yaml';
      File(pubspec).writeAsStringSync('name: x\nversion: 1.0.0\n');
      addTearDown(() => dir.deleteSync(recursive: true));
    });

    test('200 → 0 (skip the upload)', () async {
      m.pubStatus = 200;
      final r = await _run(m, ['pub-has', pubspec]);
      expect(r.exitCode, 0, reason: _out(r));
      expect(m.log.single,
          startsWith('GET /api/packages/universal_wasm_loader/versions/1.0.0'));
    });

    test('404 → 3 (publish)', () async {
      final r = await _run(m, ['pub-has', pubspec]);
      expect(r.exitCode, 3, reason: _out(r));
    });

    test('500 → 1 (cannot tell)', () async {
      m.pubStatus = 500;
      final r = await _run(m, ['pub-has', pubspec]);
      expect(r.exitCode, 1);
    });

    test('a tag that is not v<version> → 1, before any request', () async {
      final r = await _run(m, ['pub-has', pubspec], ref: 'v9.9.9');
      expect(r.exitCode, 1);
      expect(_out(r), contains('does not match'));
      expect(m.log, isEmpty);
    });
  });
}
