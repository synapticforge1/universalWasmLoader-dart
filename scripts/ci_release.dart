// The release workflow's network steps, in the owner's order (workspace
// release-process.md § 5, decision D1, 2026-11-10): checks → tag → Release
// page → publish. No GitHub CLI (workspace H30) and no package code (C30):
// this file imports only `dart:` libraries, and CI runs it from a directory
// OUTSIDE the package (or fetches it alone), so nothing is resolved or loaded
// from pub. Every network call has ONE time limit, connect to last byte
// (30 s; CI_HTTP_TIMEOUT_MS overrides it). Tests: test/ci_release_test.dart.
//
//   dart run ci_release.dart state <pubspec.yaml>          (job `checks`, U5)
//     Is this push of `main` a release? Prints `kind=new` (v<version> is not
//     on GitHub), `kind=rerun` (it is, on THIS commit) or `kind=none` (it is,
//     on another commit: an ordinary push), plus `release=` and `tag=`, also
//     appended to $GITHUB_OUTPUT when set.
//
//   dart run ci_release.dart tag [--dry-run]               (job `tag`, U6)
//     Creates the annotated tag RELEASE_TAG on GITHUB_SHA through the REST API
//     (git/tags + git/refs). Already there on this commit = done (exit 0); on
//     another commit = refused. The tag is read back (it peels to the commit).
//
//   dart run ci_release.dart github-release [--dry-run]    (job `release`, U7)
//     The GitHub Release page FROM the tag, H32's order: the tag exists and
//     peels to GITHUB_SHA (POST /releases would otherwise CREATE a missing
//     tag); an existing page = done; POST with generated notes and the pub.dev
//     link on top; read back; the tag checked again.
//
//   dart run ci_release.dart dispatch <workflow-file>      (job `dispatch`, U8)
//     Starts <workflow-file> (publish-pubdev.yml) on the ref RELEASE_TAG via
//     POST actions/workflows/<file>/dispatches (204). A tag made with
//     GITHUB_TOKEN starts no run, but a workflow_dispatch does — and pub.dev's
//     OIDC publishing takes a run whose ref is the tag (owner's pub.dev
//     setting, 2026-11-10: `v{{version}}`, workflow_dispatch events allowed).
//
//   dart run ci_release.dart verify-released               (publish-pubdev.yml)
//     In the dispatched run (RELEASE_TAG = the run's tag, GITHUB_SHA = its
//     commit): refuses unless the tag peels to GITHUB_SHA AND its GitHub
//     Release page exists, made by github-actions[bot] — proof that the main
//     run's checks passed, so a dispatch by hand on any other tag cannot
//     publish.
//
//   dart run ci_release.dart pub-has <pubspec.yaml>        (job `publish`, U8)
//     exit 0 = pub.dev already serves the version (skip the upload; re-runs
//     are safe), 3 = not yet (publish), 1 = cannot tell, or RELEASE_TAG is not
//     v<version>.
//
//   dart run ci_release.dart pub-readback <pubspec.yaml>   (job `publish`, U8)
//     After the upload, pub.dev must serve the version (polled: READBACK_TRIES,
//     default 20, READBACK_WAIT_MS apart, default 15 s); otherwise exit 1.
//
// Environment: GITHUB_REPOSITORY, GITHUB_SHA, GITHUB_TOKEN, GITHUB_OUTPUT (as
// set by Actions); RELEASE_TAG (from `checks`); GITHUB_API_URL and PUB_API_URL
// override the endpoints (for a mock server).
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
      ['state', final pubspec] => await _state(pubspec),
      ['tag'] => await _tag(dryRun: false),
      ['tag', '--dry-run'] => await _tag(dryRun: true),
      ['github-release'] => await _githubRelease(dryRun: false),
      ['github-release', '--dry-run'] => await _githubRelease(dryRun: true),
      ['dispatch', final workflow] => await _dispatch(workflow),
      ['verify-released'] => await _verifyReleased(),
      ['pub-has', final pubspec] => await _pubHas(pubspec),
      ['pub-readback', final pubspec] => await _pubReadback(pubspec),
      _ => _usage(),
    };
  } on _Refused catch (e) {
    stderr.writeln('ci_release: ${e.message}');
    code = _fail;
  }
  exit(code);
}

int _usage() {
  stderr.writeln('usage: dart run ci_release.dart state <pubspec.yaml>\n'
      '       dart run ci_release.dart tag [--dry-run]\n'
      '       dart run ci_release.dart github-release [--dry-run]\n'
      '       dart run ci_release.dart dispatch <workflow-file>\n'
      '       dart run ci_release.dart verify-released\n'
      '       dart run ci_release.dart pub-has <pubspec.yaml>\n'
      '       dart run ci_release.dart pub-readback <pubspec.yaml>');
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

String _version(String pubspecPath) {
  final src = File(pubspecPath).readAsStringSync();
  final m = RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(src);
  if (m == null) throw _Refused('no version: line in $pubspecPath');
  return m[1]!;
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

/// The repository's REST API, as Actions sets it up.
class _GitHub {
  final String base;
  final String sha;
  final String? token;

  _GitHub({required bool needToken})
      : base = '${_env('GITHUB_API_URL', fallback: 'https://api.github.com')}'
            '/repos/${_env('GITHUB_REPOSITORY')}',
        sha = _env('GITHUB_SHA'),
        token = needToken
            ? _env('GITHUB_TOKEN')
            : Platform.environment['GITHUB_TOKEN'];

  Uri u(String path) => Uri.parse('$base$path');

  Future<(int, Object?)> get(String path) =>
      _request('GET', u(path), token: token);

  Future<(int, Object?)> post(String path, Object body) =>
      _request('POST', u(path), token: token, body: body);

  /// The commit [tag] peels to (annotated tags followed), or null when the
  /// tag does not exist on GitHub.
  Future<String?> peel(String tag) async {
    var (status, json) = await get('/git/ref/tags/${Uri.encodeComponent(tag)}');
    if (status == 404) return null;
    if (status != 200) throw _Refused('GET tag ref $tag answered $status');
    var object = (json as Map)['object'] as Map;
    for (var hops = 0; object['type'] == 'tag'; hops++) {
      if (hops > 5) throw _Refused('tag $tag: too many annotated-tag hops');
      (status, json) = await get('/git/tags/${object['sha']}');
      if (status != 200) throw _Refused('GET annotated tag answered $status');
      object = (json as Map)['object'] as Map;
    }
    if (object['type'] != 'commit') {
      throw _Refused('tag $tag points at a ${object['type']}, not a commit');
    }
    return object['sha'] as String;
  }

  /// Refuses unless [tag] exists and peels to this run's commit.
  Future<void> checkTag(String tag, String when) async {
    final at = await peel(tag);
    if (at == null) throw _Refused('tag $tag does not exist on GitHub ($when)');
    if (at != sha) {
      throw _Refused('tag $tag points at commit $at, not this run\'s commit '
          '$sha ($when)');
    }
    print('tag $tag -> $sha (verified on GitHub, $when)');
  }
}

/// U5: is this push of `main` a release?
Future<int> _state(String pubspecPath) async {
  final version = _version(pubspecPath);
  final tag = 'v$version';
  final api = _GitHub(needToken: false);
  final at = await api.peel(tag);
  final kind = at == null ? 'new' : (at == api.sha ? 'rerun' : 'none');
  final lines = [
    'kind=$kind',
    'release=${kind != 'none'}',
    'tag=$tag',
    'version=$version',
  ];
  print(switch (kind) {
    'new' => '$tag is not on GitHub: this push is the release of $version',
    'rerun' => '$tag is already on this commit: a re-run of its release',
    _ => '$tag is on another commit ($at): an ordinary push, not a release',
  });
  lines.forEach(print);
  final out = Platform.environment['GITHUB_OUTPUT'];
  if (out != null && out.isNotEmpty) {
    File(out).writeAsStringSync('${lines.join('\n')}\n', mode: FileMode.append);
  }
  return _yes;
}

/// U6: CI creates the annotated tag on this run's commit.
Future<int> _tag({required bool dryRun}) async {
  final tag = _env('RELEASE_TAG');
  final api = _GitHub(needToken: !dryRun);
  final at = await api.peel(tag);
  if (at == api.sha) {
    print('tag $tag is already on $at — nothing to do');
    return _yes;
  }
  if (at != null) {
    throw _Refused('tag $tag already points at commit $at, not this run\'s '
        'commit ${api.sha}: a published tag never moves');
  }
  if (dryRun) {
    print('dry run: would create the annotated tag $tag on ${api.sha}');
    return _yes;
  }
  var (status, json) = await api.post('/git/tags', {
    'tag': tag,
    'message': tag,
    'object': api.sha,
    'type': 'commit',
  });
  if (status != 201) throw _Refused('POST git/tags $tag answered $status');
  final object = (json as Map)['sha'] as String;
  (status, json) =
      await api.post('/git/refs', {'ref': 'refs/tags/$tag', 'sha': object});
  if (status != 201 && status != 422) {
    throw _Refused('POST git/refs $tag answered $status');
  }
  // 422 = the ref appeared meanwhile; the read-back decides either way.
  await api.checkTag(tag, 'after creating it');
  print('tag $tag created (annotated, object $object)');
  return _yes;
}

/// U7: the GitHub Release page from the tag.
Future<int> _githubRelease({required bool dryRun}) async {
  final tag = _env('RELEASE_TAG');
  final api = _GitHub(needToken: !dryRun);
  final tagPath = Uri.encodeComponent(tag);

  // 1. The tag exists and peels to this run's commit.
  await api.checkTag(tag, 'before any write');

  // 2. An existing release is done; re-runs are safe.
  var (status, json) = await api.get('/releases/tags/$tagPath');
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
  (status, json) = await api.post('/releases', {
    'tag_name': tag,
    'name': tag,
    'body': '**pub.dev:** https://pub.dev/packages/universal_wasm_loader/'
        'versions/$version',
    'generate_release_notes': true,
  });
  if (status != 201) throw _Refused('POST release $tag answered $status');
  (status, json) = await api.get('/releases/tags/$tagPath');
  if (status != 200 ||
      (json as Map)['tag_name'] != tag ||
      json['draft'] != false) {
    throw _Refused('read-back of release $tag failed ($status)');
  }
  await api.checkTag(tag, 'after the POST');
  print('GitHub Release $tag created: ${json['html_url']}');
  return _yes;
}

/// U8: start the pub.dev publish workflow on the tag (OIDC needs a tag ref).
Future<int> _dispatch(String workflow) async {
  final tag = _env('RELEASE_TAG');
  final api = _GitHub(needToken: true);
  if (!RegExp(r'^[\w.-]+\.ya?ml$').hasMatch(workflow)) {
    throw _Refused('not a workflow file name: $workflow');
  }
  // The tag must already be there (the page job ran after it).
  await api.checkTag(tag, 'before the dispatch');
  final (status, _) = await api.post(
      '/actions/workflows/${Uri.encodeComponent(workflow)}/dispatches',
      {'ref': tag});
  if (status != 204) {
    throw _Refused('dispatch of $workflow on $tag answered $status');
  }
  print('dispatched $workflow on $tag');
  return _yes;
}

/// The dispatched publish run: only a tag the main run released may publish.
Future<int> _verifyReleased() async {
  final tag = _env('RELEASE_TAG');
  if (!RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(tag)) {
    throw _Refused('this run is not on a release tag (ref: $tag)');
  }
  final api = _GitHub(needToken: false);
  await api.checkTag(tag, 'the dispatched run');
  final (status, json) =
      await api.get('/releases/tags/${Uri.encodeComponent(tag)}');
  if (status == 404) {
    throw _Refused('tag $tag has no GitHub Release page: the main release run '
        'did not get past its checks, so this run may not publish');
  }
  if (status != 200) throw _Refused('GET release $tag answered $status');
  final author = ((json as Map)['author'] as Map?)?['login'];
  if (author != 'github-actions[bot]' || json['draft'] != false) {
    throw _Refused('the Release page of $tag was not made by CI '
        '(author: $author, draft: ${json['draft']}); refusing to publish');
  }
  print('tag $tag was released by CI (page by $author): may publish');
  return _yes;
}

Uri _pubVersionUrl(String version) =>
    Uri.parse('${_env('PUB_API_URL', fallback: 'https://pub.dev')}'
        '/api/packages/universal_wasm_loader/versions/'
        '${Uri.encodeComponent(version)}');

void _checkReleaseTag(String version) {
  final tag = Platform.environment['RELEASE_TAG'];
  if (tag != null && tag.isNotEmpty && tag != 'v$version') {
    throw _Refused('RELEASE_TAG $tag does not match pubspec version $version');
  }
}

/// U8: skip the upload when pub.dev already serves the version.
Future<int> _pubHas(String pubspecPath) async {
  final version = _version(pubspecPath);
  _checkReleaseTag(version);
  final url = _pubVersionUrl(version);
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

/// U8: after the upload, pub.dev must serve the version (fatal otherwise).
Future<int> _pubReadback(String pubspecPath) async {
  final version = _version(pubspecPath);
  _checkReleaseTag(version);
  final url = _pubVersionUrl(version);
  final tries =
      int.tryParse(Platform.environment['READBACK_TRIES'] ?? '') ?? 20;
  final wait = Duration(
      milliseconds:
          int.tryParse(Platform.environment['READBACK_WAIT_MS'] ?? '') ??
              15000);
  var last = 'no answer';
  for (var i = 1; i <= tries; i++) {
    final (status, json) = await _request('GET', url);
    if (status == 200 && json is Map && json['version'] == version) {
      print('read back: pub.dev serves $version (try $i)');
      return _yes;
    }
    last = status == 200 ? '200 without version $version' : '$status';
    if (i < tries) await Future<void>.delayed(wait);
  }
  throw _Refused('read-back: pub.dev does not serve $version after $tries '
      'tries (last: $last)');
}
