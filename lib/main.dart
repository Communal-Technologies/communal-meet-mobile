import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/app_update.dart';
import 'core/theme.dart';
import 'screens/home_shell.dart';
import 'screens/sign_in.dart';
import 'screens/splash.dart';
import 'state/services.dart';
import 'state/session_cubit.dart';

/// Nothing is awaited here, deliberately.
///
/// Every await before [runApp] is spent on the bare launch window with no Dart running,
/// and that is the one stretch of a cold start the app cannot draw a thing during: the
/// splash does not exist yet. So the keystore and the database are opened from [MeetApp]
/// instead, with the splash already on the screen.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  runApp(const MeetApp());
}

/// Opens the stores, then hands over to [_Gate]. Both phases draw the same splash, and
/// the floor below spans them both: it is a minimum time on screen counted from the first
/// frame, not a delay added on top of however long the boot took.
class MeetApp extends StatefulWidget {
  const MeetApp({super.key, this.services});

  /// Supplied only by tests, which have no keystore or database to boot from. When it is
  /// null — every real launch — the stores are opened by [_MeetAppState._boot].
  final AppServices? services;

  /// How long the splash is held even when there was nothing to wait for.
  ///
  /// A restored session settles in a few milliseconds, so without a floor the splash was
  /// drawn and thrown away inside one frame and the app looked like it had none — which
  /// is how this was noticed. It is not a delay for its own sake: it is the length of
  /// time it takes to read which app you have opened, and Meet is the one a member
  /// reaches for least often.
  static const _minimum = Duration(milliseconds: 1200);

  @override
  State<MeetApp> createState() => _MeetAppState();
}

class _MeetAppState extends State<MeetApp> {
  AppServices? _services;
  bool _held = true;
  String _trouble = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(MeetApp._minimum, () {
      if (mounted) setState(() => _held = false);
    });
    _services = widget.services;
    if (_services == null) _boot();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// The boot can fail two ways, and neither of them used to reach a screen.
  ///
  /// Thrown from where this used to be called — above [runApp] — the app drew nothing at
  /// all: no splash, no error, just the launch window until the member gave up. That is
  /// not a hypothetical. A build handed out with no `BASE_URL` did exactly that.
  Future<void> _boot() async {
    try {
      final services = await AppServices.boot();
      if (!mounted) return;
      setState(() => _services = services);
    } catch (error, stack) {
      // The cause goes where a developer will find it. What goes on the screen has to be
      // a sentence a member can act on, and there is only one they can act on.
      debugPrint('Meet could not boot: $error\n$stack');
      if (!mounted) return;
      setState(
        () => _trouble = error is StateError
            ? 'This build of Meet was not given a server address, so there is '
                  'nothing for it to open. It needs building again.'
            : 'Meet could not open its storage on this phone. Closing it and '
                  'opening it again usually clears this.',
      );
    }
  }

  /// The one thing to preserve here: [AppServices] and [SessionCubit] are provided
  /// **above** `MaterialApp`, not under it.
  ///
  /// A route pushed with `Navigator.push` is built by the Navigator that `MaterialApp`
  /// owns, so it inherits nothing given to `home` — it is a sibling of it, not a child.
  /// Held under `home` for one commit, and every screen reached by pushing went blank:
  /// `ThreadScreen` and `GreenRoomScreen` both read `AppServices` out of the context they
  /// are built in, found no provider, and threw where release builds draw nothing. The
  /// tabs kept working the whole time, because they are inside `home`. That is why this
  /// wrapping is not cosmetic and why there are two `MaterialApp`s below rather than one
  /// with the providers tucked inside it.
  @override
  Widget build(BuildContext context) {
    final services = _services;
    if (services == null) {
      return _app(
        _trouble.isEmpty
            ? const SplashScreen()
            : SplashScreen(message: _trouble, onRetry: _again),
      );
    }
    return RepositoryProvider.value(
      value: services,
      child: BlocProvider(
        create: (_) => SessionCubit(services)..bootstrap(),
        child: _app(_Gate(held: _held)),
      ),
    );
  }

  void _again() {
    setState(() => _trouble = '');
    _boot();
  }

  Widget _app(Widget home) => MaterialApp(
    title: 'Meet',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: home,
  );
}

class _Gate extends StatelessWidget {
  const _Gate({required this.held});

  /// The splash's floor, still running. Owned by [MeetApp] because it is measured from the
  /// first frame, which is before this widget exists.
  final bool held;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SessionCubit, SessionState>(
      builder: (context, state) {
        if (held && state.status != SessionStatus.unreachable) {
          return const SplashScreen();
        }
        switch (state.status) {
          case SessionStatus.unknown:
            return const SplashScreen();
          case SessionStatus.unreachable:
            return SplashScreen(
              message: state.notice,
              trouble: state.trouble,
              onRetry: () => context.read<SessionCubit>().refreshCaller(),
            );
          case SessionStatus.signedOut:
            return SignInScreen(notice: state.notice);
          case SessionStatus.signedIn:
            return const AppUpdateWatcher(child: HomeShell());
        }
      },
    );
  }
}
