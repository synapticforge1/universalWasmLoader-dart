// Tests for scripts/ci_release.dart (workspace H30, C34, H32, H33) against an
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
  /// missing | commit | annotated | other — what refs/tags/v1.0.0 is now.
  String tag = 'commit';
  bool moveTagAfterPost = false;
  bool releaseExists = false;
  int postStatus = 201;
  bool readBackDraft = false;
  bool stall = false;

  /// git/refs answer when CI creates the tag; on 201 / 422 the tag appears.
  int refsStatus = 201;

  /// The created tag object peels to [_other] instead of the run's commit.
  bool createdElsewhere = false;

  /// The answer to POST actions/workflows/<file>/dispatches.
  int dispatchStatus = 204;

  /// Who made the existing Release page.
  String releaseAuthor = 'github-actions[bot]';

  int pubStatus = 404;

  /// pub.dev starts serving the version at this request (0 = per [pubStatus]).
  int pubServesFrom = 0;
  String pubVersion = '1.0.0';

  final log = <String>[];
  bool _posted = false;
  int _pubGets = 0;

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
      _pubGets++;
      final serves =
          pubServesFrom > 0 ? _pubGets >= pubServesFrom : pubStatus == 200;
      if (serves) {
        send(200, {'version': pubVersion});
      } else {
        send(pubServesFrom > 0 ? 404 : pubStatus);
      }
    } else if (p.endsWith('/git/ref/tags/v1.0.0')) {
      final now = moveTagAfterPost && _posted ? 'other' : tag;
      switch (now) {
        case 'missing':
          send(404);
        case 'annotated':
          send(200, {
            'object': {'type': 'tag', 'sha': 'ttt'}
          });
        case 'created':
          send(200, {
            'object': {'type': 'tag', 'sha': 'newtag'}
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
    } else if (p.endsWith('/git/tags/newtag')) {
      send(200, {
        'object': {'type': 'commit', 'sha': createdElsewhere ? _other : _c}
      });
    } else if (p.endsWith('/git/tags') && req.method == 'POST') {
      send(201, {'sha': 'newtag'});
    } else if (p.endsWith('/git/refs') && req.method == 'POST') {
      if (refsStatus == 201 || refsStatus == 422) tag = 'created';
      send(refsStatus);
    } else if (p.endsWith('/releases/tags/v1.0.0')) {
      if (releaseExists || _posted) {
        send(200, {
          'tag_name': 'v1.0.0',
          'draft': readBackDraft,
          'html_url': 'https://example.invalid/r',
          'author': {'login': releaseAuthor},
        });
      } else {
        send(404);
      }
    } else if (p.contains('/actions/workflows/') &&
        p.endsWith('/dispatches') &&
        req.method == 'POST') {
      res.statusCode = dispatchStatus; // 204 has no body
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
    {String? token = 'test-token',
    String? tag = 'v1.0.0',
    Map<String, String> extra = const {}}) {
  // The parent environment minus everything the script reads: an EMPTY
  // environment breaks sockets on Windows (Winsock needs SystemRoot).
  final base = Map.of(Platform.environment)
    ..removeWhere((k, _) {
      final u = k.toUpperCase();
      return u.startsWith('GITHUB_') ||
          u.startsWith('READBACK_') ||
          const {'PUB_API_URL', 'CI_HTTP_TIMEOUT_MS', 'RELEASE_TAG'}
              .contains(u);
    });
  return Process.run(
    Platform.resolvedExecutable,
    ['run', 'scripts/ci_release.dart', ...args],
    environment: {
      ...base,
      'GITHUB_API_URL': m.url,
      'PUB_API_URL': m.url,
      'GITHUB_REPOSITORY': 'o/r',
      'GITHUB_REF_NAME': 'main',
      'GITHUB_SHA': _c,
      if (token != null) 'GITHUB_TOKEN': token,
      if (tag != null) 'RELEASE_TAG': tag,
      'CI_HTTP_TIMEOUT_MS': '1500',
      ...extra,
    },
    includeParentEnvironment: false,
  );
}

String _out(ProcessResult r) => '${r.stdout}${r.stderr}';

void main() {
  late _Mock m;
  late String pubspec;
  setUp(() async {
    m = _Mock();
    await m.start();
    final dir = Directory.systemTemp.createTempSync('ci_release_test');
    pubspec = '${dir.path}${Platform.pathSeparator}pubspec.yaml';
    File(pubspec).writeAsStringSync('name: x\nversion: 1.0.0\n');
    addTearDown(() => dir.deleteSync(recursive: true));
  });
  tearDown(() => m.stop());

  group('state (U5: is this push a release?)', () {
    test('tag absent → kind=new, written to GITHUB_OUTPUT', () async {
      m.tag = 'missing';
      final out = '${File(pubspec).parent.path}${Platform.pathSeparator}out';
      final r = await _run(m, ['state', pubspec],
          tag: null, extra: {'GITHUB_OUTPUT': out});
      expect(r.exitCode, 0, reason: _out(r));
      expect(File(out).readAsStringSync(),
          'kind=new\nrelease=true\ntag=v1.0.0\nversion=1.0.0\n');
    });

    test('tag on this commit (annotated) → kind=rerun', () async {
      m.tag = 'annotated';
      final r = await _run(m, ['state', pubspec], tag: null);
      expect(r.exitCode, 0, reason: _out(r));
      expect(r.stdout, contains('kind=rerun'));
      expect(r.stdout, contains('release=true'));
    });

    test('tag on another commit → kind=none (an ordinary push)', () async {
      m.tag = 'other';
      final r = await _run(m, ['state', pubspec], tag: null);
      expect(r.exitCode, 0, reason: _out(r));
      expect(r.stdout, contains('kind=none'));
      expect(r.stdout, contains('release=false'));
      expect(m.posts, 0);
    });
  });

  group('tag (U6: CI creates the tag)', () {
    test('absent: POST git/tags + git/refs, read back', () async {
      m.tag = 'missing';
      final r = await _run(m, ['tag']);
      expect(r.exitCode, 0, reason: _out(r));
      final posts = m.log.where((l) => l.startsWith('POST')).toList();
      expect(posts, hasLength(2));
      expect(posts[0], startsWith('POST /repos/o/r/git/tags auth'));
      expect(posts[0], contains('"object":"$_c"'));
      expect(posts[1], contains('"ref":"refs/tags/v1.0.0"'));
      expect(posts[1], contains('"sha":"newtag"'));
      expect(_out(r), contains('after creating it'));
    });

    test('already on this commit: done, no POST', () async {
      final r = await _run(m, ['tag']);
      expect(r.exitCode, 0, reason: _out(r));
      expect(_out(r), contains('nothing to do'));
      expect(m.posts, 0);
    });

    test('on another commit: refused, no POST', () async {
      m.tag = 'other';
      final r = await _run(m, ['tag']);
      expect(r.exitCode, 1);
      expect(_out(r), contains('never moves'));
      expect(m.posts, 0);
    });

    test('a 422 on git/refs is decided by the read-back', () async {
      m.tag = 'missing';
      m.refsStatus = 422;
      final r = await _run(m, ['tag']);
      expect(r.exitCode, 0, reason: _out(r));
    });

    test('a 500 on git/refs fails', () async {
      m.tag = 'missing';
      m.refsStatus = 500;
      final r = await _run(m, ['tag']);
      expect(r.exitCode, 1);
      expect(_out(r), contains('git/refs'));
    });

    test('a created tag that peels elsewhere fails the read-back', () async {
      m.tag = 'missing';
      m.createdElsewhere = true;
      final r = await _run(m, ['tag']);
      expect(r.exitCode, 1);
      expect(_out(r), contains('after creating it'));
    });

    test('--dry-run sends no POST', () async {
      m.tag = 'missing';
      final r = await _run(m, ['tag', '--dry-run']);
      expect(r.exitCode, 0, reason: _out(r));
      expect(m.posts, 0);
    });

    test('no RELEASE_TAG or no token: refused before any request', () async {
      var r = await _run(m, ['tag'], tag: null);
      expect(r.exitCode, 1);
      expect(_out(r), contains('RELEASE_TAG'));
      r = await _run(m, ['tag'], token: null);
      expect(r.exitCode, 1);
      expect(_out(r), contains('GITHUB_TOKEN'));
      expect(m.log, isEmpty);
    });
  });

  group('github-release (U7: the page from the tag)', () {
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

  group('dispatch (U8: start the pub.dev run on the tag)', () {
    test('204: one POST with the tag as ref, token sent', () async {
      final r = await _run(m, ['dispatch', 'publish-pubdev.yml']);
      expect(r.exitCode, 0, reason: _out(r));
      final post = m.log.singleWhere((l) => l.startsWith('POST'));
      expect(
          post,
          startsWith('POST /repos/o/r/actions/workflows/publish-pubdev.yml/'
              'dispatches auth'));
      expect(post, contains('"ref":"v1.0.0"'));
    });

    test('a refused dispatch (403) fails', () async {
      m.dispatchStatus = 403;
      final r = await _run(m, ['dispatch', 'publish-pubdev.yml']);
      expect(r.exitCode, 1);
      expect(_out(r), contains('403'));
    });

    test('no tag yet: refused, no POST', () async {
      m.tag = 'missing';
      final r = await _run(m, ['dispatch', 'publish-pubdev.yml']);
      expect(r.exitCode, 1);
      expect(m.posts, 0);
    });

    test('not a workflow file name, or no token: refused before any request',
        () async {
      var r = await _run(m, ['dispatch', '../x']);
      expect(r.exitCode, 1);
      r = await _run(m, ['dispatch', 'publish-pubdev.yml'], token: null);
      expect(r.exitCode, 1);
      expect(m.log, isEmpty);
    });
  });

  group('verify-released (the dispatched run may publish?)', () {
    test('tag on this commit and a page by github-actions[bot] → 0', () async {
      m.releaseExists = true;
      final r = await _run(m, ['verify-released']);
      expect(r.exitCode, 0, reason: _out(r));
    });

    test('no Release page → refused', () async {
      final r = await _run(m, ['verify-released']);
      expect(r.exitCode, 1);
      expect(_out(r), contains('no GitHub Release page'));
    });

    test('a page made by a person → refused', () async {
      m.releaseExists = true;
      m.releaseAuthor = 'someone';
      final r = await _run(m, ['verify-released']);
      expect(r.exitCode, 1);
      expect(_out(r), contains('not made by CI'));
    });

    test('a tag on another commit → refused', () async {
      m.releaseExists = true;
      m.tag = 'other';
      final r = await _run(m, ['verify-released']);
      expect(r.exitCode, 1);
    });

    test('a run not on a release tag (ref main) → refused, no request',
        () async {
      final r = await _run(m, ['verify-released'], tag: 'main');
      expect(r.exitCode, 1);
      expect(_out(r), contains('not on a release tag'));
      expect(m.log, isEmpty);
    });
  });

  group('pub-has (U8: skip if published)', () {
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

    test('RELEASE_TAG that is not v<version> → 1, before any request',
        () async {
      final r = await _run(m, ['pub-has', pubspec], tag: 'v9.9.9');
      expect(r.exitCode, 1);
      expect(_out(r), contains('does not match'));
      expect(m.log, isEmpty);
    });
  });

  group('pub-readback (U8: fatal read-back)', () {
    const fast = {'READBACK_TRIES': '4', 'READBACK_WAIT_MS': '20'};

    test('served at once → 0', () async {
      m.pubStatus = 200;
      final r = await _run(m, ['pub-readback', pubspec], extra: fast);
      expect(r.exitCode, 0, reason: _out(r));
      expect(r.stdout, contains('try 1'));
    });

    test('served after two 404s → 0 on the third try', () async {
      m.pubServesFrom = 3;
      final r = await _run(m, ['pub-readback', pubspec], extra: fast);
      expect(r.exitCode, 0, reason: _out(r));
      expect(r.stdout, contains('try 3'));
    });

    test('never served → 1 after the tries', () async {
      final r = await _run(m, ['pub-readback', pubspec], extra: fast);
      expect(r.exitCode, 1);
      expect(_out(r), contains('after 4 tries'));
      expect(m.log, hasLength(4));
    });

    test('200 for another version → 1', () async {
      m.pubStatus = 200;
      m.pubVersion = '0.9.9';
      final r = await _run(m, ['pub-readback', pubspec], extra: fast);
      expect(r.exitCode, 1);
      expect(_out(r), contains('without version'));
    });
  });
}
