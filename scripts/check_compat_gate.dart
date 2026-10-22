// Self-test of the compatibility gate's decisions (scripts/compat.dart), with
// no git, no Chrome and no network: every rule must REFUSE when it should, not
// only allow (workspace best-practices 2.1: a gate that cannot fail is
// decoration). Mirrors the `-js` reference's `scripts/check-compat-gate.ts`.
//
// Run via:  dart run scripts/check_compat_gate.dart

import 'dart:io';

import 'compat.dart';
import 'surface.dart';

var _passed = 0;
final _failed = <String>[];

void check(String name, bool ok) {
  if (ok) {
    _passed++;
  } else {
    _failed.add(name);
  }
}

bool throws(void Function() f) {
  try {
    f();
    return false;
  } on FormatException {
    return true;
  }
}

Surface s(Map<String, String> symbols, [String spec = '3.0.0']) =>
    Surface(spec, symbols);

const readmeNoRow = '''
### ⚠️ Breaking Changes

| Version | What changed | How to migrate |
| --- | --- | --- |
| 0.2.0 | old | old |

## Testing
| _next release_ | outside the section | — |
''';
const readmeRow = '''
### ⚠️ Breaking Changes

| Version | What changed | How to migrate |
| --- | --- | --- |
| _next release_ | x removed | use y |
| 0.2.0 | old | old |

## Testing
''';

List<String> p({
  String floor = 'patch',
  bool testsOk = true,
  bool surfaceCurrent = true,
  String? kind = 'patch',
  String from = '1.2.3',
  String readme = readmeNoRow,
}) =>
    problemsFor(
      floor: floor,
      testsOk: testsOk,
      surfaceCurrent: surfaceCurrent,
      kind: kind,
      from: from,
      readme: readme,
      rowLabel: '_next release_',
    );

void main() {
  // bumpKind / parseVersion
  check('bumpKind patch', bumpKind('0.2.0', '0.2.1') == 'patch');
  check('bumpKind minor', bumpKind('0.2.9', '0.3.0') == 'minor');
  check('bumpKind major', bumpKind('0.2.0', '1.0.0') == 'major');
  check('bumpKind refuses same', throws(() => bumpKind('1.0.0', '1.0.0')));
  check('bumpKind refuses lower', throws(() => bumpKind('1.2.0', '1.1.9')));
  check('parseVersion refuses junk', throws(() => parseVersion('1.2')));
  check('parseVersion refuses suffix', throws(() => parseVersion('1.2.3-dev')));

  // floorOf
  final base = {'a': 'int a()', 'b': 'void b(String x)'};
  check(
      'floor nothing → patch', floorOf(s(base), s({...base})).floor == 'patch');
  check('floor added → minor',
      floorOf(s(base), s({...base, 'c': 'void c()'})).floor == 'minor');
  check('floor removed → major',
      floorOf(s(base), s({'a': 'int a()'})).floor == 'major');
  check('floor changed → major',
      floorOf(s(base), s({...base, 'b': 'void b(int x)'})).floor == 'major');
  final removed = floorOf(s(base), s({'a': 'int a()'}));
  check('floor names the removed symbol',
      removed.reasons.any((r) => r.contains('symbol removed: b')));
  check('floor spec minor → minor',
      floorOf(s(base), s(base, '3.1.0')).floor == 'minor');
  check('floor spec major → major',
      floorOf(s(base), s(base, '4.0.0')).floor == 'major');
  check('floor spec lowered → major',
      floorOf(s(base, '3.1.0'), s(base, '3.0.0')).floor == 'major');

  // hasBreakingRow
  check('row found in section', hasBreakingRow(readmeRow, '_next release_'));
  check('row outside section ignored',
      !hasBreakingRow(readmeNoRow, '_next release_'));
  check('no section → no row', !hasBreakingRow('# x\n', '_next release_'));

  // problemsFor
  check('patch at patch floor allowed', p().isEmpty);
  check('report mode allows anything at patch', p(kind: null).isEmpty);
  check('patch below minor floor refused', p(floor: 'minor').isNotEmpty);
  check(
      'minor at minor floor allowed', p(floor: 'minor', kind: 'minor').isEmpty);
  check('stale surface refused', p(surfaceCurrent: false).isNotEmpty);
  check('red tests refuse patch', p(testsOk: false).isNotEmpty);
  check('red tests refuse minor',
      p(floor: 'minor', kind: 'minor', testsOk: false).isNotEmpty);
  check(
      'red tests allow major (with row)',
      p(floor: 'major', kind: 'major', testsOk: false, readme: readmeRow)
          .isEmpty);
  check('1.x minor below major floor refused',
      p(floor: 'major', kind: 'minor', readme: readmeRow).isNotEmpty);
  check(
      '0.x minor at major floor allowed with row',
      p(floor: 'major', kind: 'minor', from: '0.2.0', readme: readmeRow)
          .isEmpty);
  check('0.x minor at major floor refused without row',
      p(floor: 'major', kind: 'minor', from: '0.2.0').isNotEmpty);
  check(
      '0.x patch at major floor refused',
      p(floor: 'major', kind: 'patch', from: '0.2.0', readme: readmeRow)
          .isNotEmpty);
  check('major floor without row refused even for major',
      p(floor: 'major', kind: 'major').isNotEmpty);

  final total = _passed + _failed.length;
  if (_failed.isNotEmpty) {
    stderr
        .writeln('❌ compat gate self-test: ${_failed.length} of $total failed');
    for (final f in _failed) {
      stderr.writeln('  $f');
    }
    exit(1);
  }
  print('✅ compat gate self-test: $total of $total checks pass');
}
