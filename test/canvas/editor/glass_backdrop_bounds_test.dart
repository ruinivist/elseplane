import 'dart:math' as math;
import 'dart:ui';

import 'package:elseplane/canvas/editor/glass_backdrop_bounds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const card = Rect.fromLTWH(0, 0, 100, 50);

  test('exact sampling contact and blocker paint outsets prevent skipping blur', () {
    Set<String> clearWithBlockerAt(double left, {double outset = 0}) => glassCardsWithClearBackdrop([
      _footprint('blocker', Rect.fromLTWH(left, 0, 20, 20), outset: outset),
      _footprint('card', card, glass: true),
    ]);

    expect(clearWithBlockerAt(132), isEmpty);
    expect(clearWithBlockerAt(132.1), {'card'});
    expect(clearWithBlockerAt(140, outset: 8), isEmpty);
    expect(clearWithBlockerAt(140.1, outset: 8), {'card'});
  });

  test('rotation can turn nearby paint into a blocker', () {
    const blocker = Rect.fromLTWH(137, 0, 10, 40);
    Set<String> clearAt(double rotation) => glassCardsWithClearBackdrop([
      _footprint('blocker', rotatedBackdropBounds(blocker, rotation)),
      _footprint('card', card, glass: true),
    ]);
    expect(clearAt(0), {'card'});
    expect(clearAt(math.pi / 2), isEmpty);
  });

  test('clamping a code layout pivot does not shrink the full height of its paint', () {
    const code = Rect.fromLTWH(0, 300, 200, 634);
    const note = Rect.fromLTWH(0, 75, 100, 135);
    Set<String> clearAt(double rotation) => glassCardsWithClearBackdrop([
      _footprint('code', rotatedBackdropBounds(code, rotation)),
      _footprint('note', note, glass: true),
    ]);
    expect(clearAt(0), {'note'});
    // At 180°, a 400px layout height shifts the 634px painted body up by 234px.
    expect(clearAt(math.pi), isEmpty);
  });

  test('unknown paint only invalidates itself and later backdrops', () {
    expect(
      glassCardsWithClearBackdrop([
        _footprint('earlier', card, glass: true),
        _footprint('unknown', null, glass: true),
        _footprint('later', card.shift(const Offset(1000, 0)), glass: true),
      ]),
      {'earlier'},
    );
  });
}

MapEntry<String, GlassBackdropFootprint> _footprint(
  String id,
  Rect? bounds, {
  double outset = 0,
  bool glass = false,
}) => MapEntry(id, (bounds: bounds, glass: glass, paintOutset: outset));
