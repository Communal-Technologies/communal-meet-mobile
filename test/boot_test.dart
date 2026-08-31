import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:communal_meet/core/config.dart';
import 'package:communal_meet/main.dart';
import 'package:communal_meet/screens/sign_in.dart';
import 'package:communal_meet/screens/splash.dart';
import 'package:communal_meet/state/services.dart';
import 'package:communal_meet/state/session_cubit.dart';

void main() {
  group('MeetApp', () {
    setUp(() => AppConfig.testBaseUrl = 'http://127.0.0.1:8989');
    tearDown(() => AppConfig.testBaseUrl = null);

    /// The regression this file exists for, and it cost a member two blank screens.
    ///
    /// A route pushed with `Navigator.push` is built by the Navigator `MaterialApp` owns,
    /// so it is a *sibling* of whatever `home` is, not a child of it. Providers given to
    /// `home` are therefore invisible to every pushed screen: opening a chat or a meeting
    /// died on `Provider<AppServices> not found for _InheritedProviderScope<ThreadCubit?>`
    /// at `thread.dart:25`, which in a release build is a white screen and no words. The
    /// tabs went on working the whole time, because they live inside `home` — which is
    /// what made it look like the chat screen was at fault.
    ///
    /// So: above `MaterialApp`, and asserted on the tree rather than trusted to a comment.
    testWidgets('provides AppServices above the Navigator, not inside it', (
      tester,
    ) async {
      await tester.pumpWidget(MeetApp(services: AppServices.unopened()));
      await tester.pump(const Duration(milliseconds: 1400));

      for (final provider in [
        find.byType(RepositoryProvider<AppServices>),
        find.byType(BlocProvider<SessionCubit>),
      ]) {
        expect(provider, findsOneWidget);
        expect(
          find.ancestor(of: find.byType(MaterialApp), matching: provider),
          findsOneWidget,
          reason:
              'a pushed route cannot see a provider that sits under MaterialApp',
        );
      }
    });

    /// The same thing said from the far end: a screen pushed the way `openThread` and
    /// `openMeeting` push must be able to read what it needs. This is the assertion that
    /// would have failed on the shipped build; the one above only says where the provider
    /// is, and this one says the push works.
    testWidgets('a pushed route can still read AppServices', (tester) async {
      await tester.pumpWidget(MeetApp(services: AppServices.unopened()));
      await tester.pump(const Duration(milliseconds: 1400));

      AppServices? seen;
      // Not awaited: a push completes when the route is *popped*, so awaiting it here
      // waits for a screen nobody is going to close.
      Navigator.of(tester.element(find.byType(SignInScreen))).push(
        MaterialPageRoute(
          builder: (routeContext) {
            seen = routeContext.read<AppServices>();
            return const SizedBox.shrink();
          },
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(seen, isNotNull);
    });

    /// An unopened store holds no token, so the boot has nowhere to go but sign-in. Worth
    /// pinning because it is the path the two tests above stand on.
    testWidgets('an unopened session lands on sign-in, not on the splash', (
      tester,
    ) async {
      await tester.pumpWidget(MeetApp(services: AppServices.unopened()));

      expect(find.byType(SplashScreen), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1400));
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.byType(SplashScreen), findsNothing);
    });
  });
}
