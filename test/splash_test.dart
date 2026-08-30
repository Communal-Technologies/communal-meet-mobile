import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:communal_meet/core/theme.dart';
import 'package:communal_meet/data/api_client.dart';
import 'package:communal_meet/screens/splash.dart';

Widget _app(Widget child) =>
    MaterialApp(theme: buildAppTheme(), home: child);

void main() {
  group('SplashScreen', () {
    for (final size in const [Size(320, 568), Size(430, 932), Size(800, 1280)]) {
      testWidgets('lays out at ${size.width}x${size.height}', (tester) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_app(const SplashScreen()));
        await tester.pump(const Duration(milliseconds: 700));

        expect(tester.takeException(), isNull);
        expect(find.byType(Image), findsOneWidget);
      });
    }

    /// Meet is the one of the three that opens white. If this ever goes purple again the
    /// Dart splash becomes the same colour as the launch window Android paints, and a
    /// cold start reads as an app with no splash at all — which is how this screen was
    /// first noticed to be missing.
    testWidgets('opens on white, not on the brand purple', (tester) async {
      await tester.pumpWidget(_app(const SplashScreen()));

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, AppColors.white);
    });

    /// A bar that flashes for a fifth of a second reads as a glitch, so it waits.
    testWidgets('the loader stays out of the way for the first 400ms', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const SplashScreen()));

      double opacityNow() =>
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

      expect(opacityNow(), 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(opacityNow(), 0);
      await tester.pump(const Duration(milliseconds: 300));
      expect(opacityNow(), 1);
    });

    /// The reason this screen was rewritten: the app said "you are offline" to somebody
    /// whose phone had a network the whole time.
    testWidgets('names the trouble the phone actually reported', (tester) async {
      await tester.pumpWidget(
        _app(
          SplashScreen(
            trouble: Trouble.unreachable,
            message: '',
            onRetry: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('Cannot reach Communal'), findsOneWidget);
      expect(find.text('No network on this phone'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);

      await tester.pumpWidget(
        _app(SplashScreen(trouble: Trouble.offline, onRetry: () {})),
      );
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('No network on this phone'), findsOneWidget);
      expect(find.text('Cannot reach Communal'), findsNothing);
    });

    testWidgets('a failure that came with words uses them', (tester) async {
      await tester.pumpWidget(
        _app(
          SplashScreen(
            trouble: Trouble.failed,
            message: 'Your session expired.',
            onRetry: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('Your session expired.'), findsOneWidget);
      expect(find.byType(AnimatedOpacity), findsNothing);
    });
  });
}
