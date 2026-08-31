import 'package:flutter_test/flutter_test.dart';

import 'package:communal_meet/core/grid.dart';

void main() {
  group('gridLayout', () {
    test('an unmeasured stage reports itself rather than guessing', () {
      final layout = gridLayout(
        count: 4,
        width: 0,
        height: 0,
        aspect: tileAspectPortrait,
      );
      expect(layout.measured, isFalse);
      expect(layout.columns, 1);
    });

    test('one person takes the whole stage', () {
      final layout = gridLayout(
        count: 1,
        width: 360,
        height: 560,
        aspect: tileAspectPortrait,
      );
      expect(layout.columns, 1);
      expect(layout.rows, 1);
      // Bounded by the width, not the height: 360 wide at 3:4 is 480 tall, and
      // there are 560 to spend.
      expect(layout.tileWidth, closeTo(360, 0.01));
    });

    test('four on a portrait phone go two by two', () {
      final layout = gridLayout(
        count: 4,
        width: 360,
        height: 560,
        aspect: tileAspectPortrait,
      );
      expect(layout.columns, 2);
      expect(layout.rows, 2);
      expect(layout.tileWidth, closeTo((360 - tileGap) / 2, 0.01));
    });

    test('the tile never exceeds the height it is given', () {
      final layout = gridLayout(
        count: 2,
        width: 800,
        height: 300,
        aspect: tileAspectLandscape,
      );
      expect(layout.rows * layout.tileHeight + tileGap * (layout.rows - 1),
          lessThanOrEqualTo(300.01));
    });

    test('the largest tile wins, whatever the column count that needs', () {
      const width = 700.0;
      const height = 400.0;
      final best = gridLayout(
        count: 3,
        width: width,
        height: height,
        aspect: tileAspectLandscape,
      );
      for (var columns = 1; columns <= 3; columns++) {
        final rows = (3 / columns).ceil();
        final byWidth = (width - tileGap * (columns - 1)) / columns;
        final byHeight =
            ((height - tileGap * (rows - 1)) / rows) * tileAspectLandscape;
        final candidate = byWidth < byHeight ? byWidth : byHeight;
        expect(best.tileWidth, greaterThanOrEqualTo(candidate - 0.01));
      }
    });

    test('an odd count leaves the last row short rather than dropping anyone', () {
      final layout = gridLayout(
        count: 5,
        width: 360,
        height: 700,
        aspect: tileAspectPortrait,
      );
      expect(layout.columns * layout.rows, greaterThanOrEqualTo(5));
    });
  });

  group('tilesPerPage', () {
    test('an unmeasured stage takes the cap', () {
      expect(
        tilesPerPage(
          width: 0,
          height: 0,
          aspect: tileAspectPortrait,
          cap: 12,
        ),
        12,
      );
    });

    test('never returns zero, however small the stage', () {
      expect(
        tilesPerPage(
          width: 80,
          height: 60,
          aspect: tileAspectPortrait,
          cap: 12,
        ),
        1,
      );
    });

    test('every tile on a full page is still legible', () {
      const width = 360.0;
      const height = 560.0;
      final n = tilesPerPage(
        width: width,
        height: height,
        aspect: tileAspectPortrait,
        cap: 12,
      );
      final layout = gridLayout(
        count: n,
        width: width,
        height: height,
        aspect: tileAspectPortrait,
      );
      expect(n, greaterThanOrEqualTo(1));
      if (n > 1) {
        expect(layout.tileWidth, greaterThanOrEqualTo(minTileWidth));
      }
    });

    test('a bigger stage holds at least as many as a smaller one', () {
      final small = tilesPerPage(
        width: 320,
        height: 500,
        aspect: tileAspectPortrait,
        cap: 12,
      );
      final large = tilesPerPage(
        width: 800,
        height: 1200,
        aspect: tileAspectPortrait,
        cap: 12,
      );
      expect(large, greaterThanOrEqualTo(small));
    });

    test('the cap is a ceiling, not a target', () {
      expect(
        tilesPerPage(
          width: 4000,
          height: 4000,
          aspect: tileAspectPortrait,
          cap: 12,
        ),
        12,
      );
    });
  });
}
