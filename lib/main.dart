import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
          title: 'Communal Meet',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: const _Gate(),
        ),
      ),
    );
  }
}

class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SessionCubit, SessionState>(
      builder: (context, state) {
        switch (state.status) {
          case SessionStatus.unknown:
            return const SplashScreen();
          case SessionStatus.unreachable:
            return SplashScreen(
              message: state.notice,
              onRetry: () => context.read<SessionCubit>().refreshCaller(),
            );
          case SessionStatus.signedOut:
            return SignInScreen(notice: state.notice);
          case SessionStatus.signedIn:
            return const HomeShell();
        }
      },
    );
  }
}
