/// Tile layout for the meeting grid, decided from the stage's measured size rather
/// than the head count.
///
/// Ported from `livekit-fe/src/lib/grid.ts`, so a phone and a browser in the same
/// meeting divide the stage by the same rule. The one change is the aspect: the
/// browser holds tiles at the camera's 16:9 always, and on a portrait phone that
/// leaves half the screen empty, so portrait holds 3:4 and only landscape is the
/// reference's exact behaviour.
library;

/// The camera's own shape, and what a landscape phone uses.
const double tileAspectLandscape = 16 / 9;

/// Portrait. Wider than the phone itself, so two tiles still sit side by side, but
/// tall enough that four of them fill the stage instead of stranding a band of
/// black at each end.
const double tileAspectPortrait = 3 / 4;

/// Below this a face is unrecognisable and the name label no longer fits.
const double minTileWidth = 150;

/// The default gap between tiles, in logical pixels.
const double tileGap = 12;

class GridLayout {
  const GridLayout({
    required this.columns,
    required this.rows,
    required this.tileWidth,
    required this.aspect,
  });

  final int columns;
  final int rows;

  /// Width of one tile in logical pixels. Zero means the stage has not been
  /// measured yet, and the caller should draw a placeholder rather than a guess
  /// that would flash for one frame.
  final double tileWidth;

  final double aspect;

  double get tileHeight => tileWidth / aspect;
  bool get measured => tileWidth > 0;
}

/// The largest tile [count] tiles can have in a [width] × [height] box.
///
/// Every column count is tried and the one that makes the tile largest wins.
/// Bounded by the height as well as the width, or a landscape phone would run the
/// bottom row off the screen.
GridLayout gridLayout({
  required int count,
  required double width,
  required double height,
  required double aspect,
  double gap = tileGap,
}) {
  if (count <= 0 || width <= 0 || height <= 0) {
    return GridLayout(columns: 1, rows: 1, tileWidth: 0, aspect: aspect);
  }

  var best = GridLayout(
    columns: 1,
    rows: count,
    tileWidth: 0,
    aspect: aspect,
  );
  for (var columns = 1; columns <= count; columns++) {
    final rows = (count / columns).ceil();
    final byWidth = (width - gap * (columns - 1)) / columns;
    final byHeight = ((height - gap * (rows - 1)) / rows) * aspect;
    final tileWidth = byWidth < byHeight ? byWidth : byHeight;
    if (tileWidth > best.tileWidth) {
      best = GridLayout(
        columns: columns,
        rows: rows,
        tileWidth: tileWidth,
        aspect: aspect,
      );
    }
  }
  return best;
}

/// How many tiles fit on one page before they stop being legible.
///
/// Counts down from [cap] because the best layout for n tiles is not monotonic in
/// n — 3 tiles can be larger than 2 in a wide box — so probing upwards can stop
/// one short of a size that does fit. Never returns 0: one tile always shows,
/// however small the stage.
int tilesPerPage({
  required double width,
  required double height,
  required double aspect,
  required int cap,
  double gap = tileGap,
}) {
  if (width <= 0 || height <= 0) return cap;
  for (var n = cap; n > 1; n--) {
    final layout = gridLayout(
      count: n,
      width: width,
      height: height,
      aspect: aspect,
      gap: gap,
    );
    if (layout.tileWidth >= minTileWidth) return n;
  }
  return 1;
}
