// The release workflow's two network steps, with no GitHub CLI (workspace H30)
// and no package code (workspace C30): this file imports only `dart:`
// libraries, and CI runs it from a directory OUTSIDE the package, so nothing is
// resolved or loaded from pub. `pub-has` runs in the `publish` job; the
// `release` job fetches only this file and runs `github-release` (H32).
// Every network call has one time limit, connect to last byte (30 s;
// CI_HTTP_TIMEOUT_MS overrides it). Tests: test/ci_release_test.dart.
//
//   dart run ci_release.dart pub-has <path/to/pubspec.yaml>
//     Is this pubspec's version already on pub.dev? exit 0 = yes (skip the
//     upload, so a re-run after a later failure can finish), 3 = no (publish),
//     1 = could not tell, or the tag does not match the version.
//
//   dart run ci_release.dart github-release [--dry-run]
//     Creates the GitHub Release for GITHUB_REF_NAME through the REST API with
//     GITHUB_TOKEN. Refuses unless the tag already exists on GitHub and peels to
//     GITHUB_SHA (POST /releases would otherwise CREATE a missing tag from the
//     default branch). An existing release counts as done (exit 0). After a
//     201 the release is read back and the tag is checked again. --dry-run
//     sends no POST.
//
// Environment: GITHUB_REPOSITORY, GITHUB_REF_NAME, GITHUB_SHA, GITHUB_TOKEN
// (as set by Actions); GITHUB_API_URL and PUB_API_URL override the endpoints
// (for a mock server).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _yes = 0;
const _no = 3;
const _fail = 1;

Future<void> main(List<String> args) async {
  int code;
  try {
    code = switch (args) {
      ['pub-has', final pubspec] => await _pubHas(pubspec),
      ['github-release'] => await _githubRelease(dryRun: false),
      ['github-release', '--dry-run'] => await _githubRelease(dryRun: true),
      _ => _usage(),
    };
  } on _Refused catch (e) {
    stderr.writeln('ci_release: ${e.message}');
    code = _fail;
  }
  exit(code);
}

int _usage() {
  stderr.writeln('usage: dart run ci_release.dart pub-has <pubspec.yaml>\n'
      '       dart run ci_release.dart github-release [--dry-run]');
  return 64;
}

class _Refused implements Exception {
  final String message;
  _Refused(this.message);
}

String _env(String name, {String? fallback}) {
  final v = Platform.environment[name];
  if (v != null && v.isNotEmpty) return v;
  if (fallback != null) return fallback;
  throw _Refused('$name is not set');
}

/// The time limit of each network call, from the connect to the last byte of
/// the body (workspace best-practices 7.21). CI_HTTP_TIMEOUT_MS overrides the
/// default 30 s (for the tests' stalled-server case).
final _limit = Duration(
    milliseconds:
        int.tryParse(Platform.environment['CI_HTTP_TIMEOUT_MS'] ?? '') ??
            30000);

final _client = HttpClient()
  ..userAgent = 'universalWasmLoader-dart-ci'
  ..connectionTimeout = _limit;

/// One HTTP request; returns (status, decoded JSON body or null). The whole
/// call — connect, send, headers, body — runs under ONE time limit.
Future<(int, Object?)> _request(String method, Uri url,
    {String? token, Object? body}) async {
  Future<(int, Object?)> call() async {
    final req = await _client.openUrl(method, url);
    req.headers.set('Accept', 'application/vnd.github+json');
    req.headers.set('X-GitHub-Api-Version', '2022-11-28');
    if (token != null) req.headers.set('Authorization', 'Bearer $token');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    Object? json;
    try {
      json = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      json = null;
    }
    return (res.statusCode, json);
  }

  try {
    return await call().timeout(_limit);
  } on TimeoutException {
    throw _Refused('$method $url timed out after ${_limit.inMilliseconds} ms');
  } on SocketException catch (e) {
    throw _Refused('$method $url failed: ${e.message}');
  }
}

Future<int> _pubHas(String pubspecPath) async {
  final src = File(pubspecPath).readAsStringSync();
  final m = RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(src);
  if (m == null) throw _Refused('no version: line in $pubspecPath');
  final version = m[1]!;
  final tag = Platform.environment['GITHUB_REF_NAME'];
  if (tag != null && tag.isNotEmpty && tag != 'v$version') {
    throw _Refused('tag $tag does not match pubspec version $version');
  }
  final api = _env('PUB_API_URL', fallback: 'https://pub.dev');
  final url = Uri.parse('$api/api/packages/universal_wasm_loader/versions/'
      '${Uri.encodeComponent(version)}');
  final (status, _) = await _request('GET', url);
  switch (status) {
    case 200:
      print('pub.dev already has $version — the upload is skipped');
      return _yes;
    case 404:
      print('pub.dev does not have $version yet — publish it');
      return _no;
    default:
      throw _Refused('pub.dev answered $status for $url');
  }
}

Future<int> _githubRelease({required bool dryRun}) async {
  final api = _env('GITHUB_API_URL', fallback: 'https://api.github.com');
  final repo = _env('GITHUB_REPOSITORY');
  final tag = _env('GITHUB_REF_NAME');
  final sha = _env('GITHUB_SHA');
  final token =
      dryRun ? Platform.environment['GITHUB_TOKEN'] : _env('GITHUB_TOKEN');
  final base = '$api/repos/$repo';
  Uri u(String path) => Uri.parse('$base$path');
  final tagPath = Uri.encodeComponent(tag);

  // The tag must exist on GitHub and peel (annotated tags followed) to this
  // run's commit. Checked before any write, and again after the POST.
  Future<void> checkTag(String when) async {
    var (status, json) =
        await _request('GET', u('/git/ref/tags/$tagPath'), token: token);
    if (status == 404) {
      throw _Refused('tag $tag does not exist on GitHub ($when)');
    }
    if (status != 200) throw _Refused('GET tag ref $tag answered $status');
    var object = (json as Map)['object'] as Map;
    for (var hops = 0; object['type'] == 'tag'; hops++) {
      if (hops > 5) throw _Refused('tag $tag: too many annotated-tag hops');
      (status, json) =
          await _request('GET', u('/git/tags/${object['sha']}'), token: token);
      if (status != 200) throw _Refused('GET annotated tag answered $status');
      object = (json as Map)['object'] as Map;
    }
    if (object['type'] != 'commit' || object['sha'] != sha) {
      throw _Refused('tag $tag points at ${object['type']} ${object['sha']}, '
          'not this run\'s commit $sha ($when)');
    }
    print('tag $tag -> $sha (verified on GitHub, $when)');
  }

  // 1. The tag exists and peels to this run's commit.
  await checkTag('before any write');

  // 2. An existing release is done; re-runs are safe.
  var (status, json) =
      await _request('GET', u('/releases/tags/$tagPath'), token: token);
  if (status == 200) {
    print('GitHub Release $tag already exists — nothing to do');
    return _yes;
  }
  if (status != 404) throw _Refused('GET release $tag answered $status');

  if (dryRun) {
    print('dry run: would POST the GitHub Release $tag');
    return _yes;
  }

  // 3. Create it (the pub.dev link on top of GitHub's generated notes), read
  //    it back, and check that the tag still peels to this run's commit.
  final version = tag.startsWith('v') ? tag.substring(1) : tag;
  (status, json) = await _request('POST', u('/releases'), token: token, body: {
    'tag_name': tag,
    'name': tag,
    'body': '**pub.dev:** https://pub.dev/packages/universal_wasm_loader/'
        'versions/$version',
    'generate_release_notes': true,
  });
  if (status != 201) throw _Refused('POST release $tag answered $status');
  (status, json) =
      await _request('GET', u('/releases/tags/$tagPath'), token: token);
  if (status != 200 ||
      (json as Map)['tag_name'] != tag ||
      json['draft'] != false) {
    throw _Refused('read-back of release $tag failed ($status)');
  }
  await checkTag('after the POST');
  print('GitHub Release $tag created: ${json['html_url']}');
  return _yes;
}
