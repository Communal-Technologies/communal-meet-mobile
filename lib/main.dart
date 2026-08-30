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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  final services = await AppServices.boot();
  runApp(MeetApp(services: services));
}

class MeetApp extends StatelessWidget {
  const MeetApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider.value(
      value: services,
      child: BlocProvider(
        create: (_) => SessionCubit(services)..bootstrap(),
        child: MaterialApp(
          title: 'Meet',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: const _Gate(),
        ),
      ),
    );
  }
}

class _Gate extends StatefulWidget {
  const _Gate();

  /// How long the splash is held even when there was nothing to wait for.
  ///
  /// A restored session settles in a few milliseconds, so without a floor the splash
  /// was drawn and thrown away inside one frame and the app looked like it had none —
  /// which is how this was noticed. It is not a delay for its own sake: it is the
  /// length of time it takes to read which app you have opened, and Meet is the one a
  /// member reaches for least often.
  static const _minimum = Duration(milliseconds: 1200);

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  bool _held = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_Gate._minimum, () {
      if (mounted) setState(() => _held = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SessionCubit, SessionState>(
      builder: (context, state) {
        if (_held && state.status != SessionStatus.unreachable) {
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
