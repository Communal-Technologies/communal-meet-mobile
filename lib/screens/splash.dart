import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../data/api_client.dart';
import '../widgets/states.dart';

/// What Meet opens on.
///
/// White, with the purple mark. That is the one of the three fleet apps that does not
/// open on a dark screen — the wallet and the collector both open on black — so a
/// member knows which app they launched before a word is read. It is also the colour
/// of the launch window Android paints before any Dart runs, and the colour Home is,
/// so a cold start is one continuous screen rather than two flashes.
///
/// There is deliberately nothing to watch. The loader waits [_loaderAfter] before it
/// appears: a restored session usually resolves sooner than that, and a bar that
/// flashes for a fifth of a second reads as a glitch rather than as progress.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.message = '',
    this.trouble = Trouble.failed,
    this.onRetry,
  });

  /// What went wrong, in the app's own words. Empty while the session is still being
  /// worked out.
  final String message;

  /// Which of the three troubles it was. It decides the heading, and the heading is
  /// the part a member reads: telling somebody they are offline while they are looking
  /// at four bars of signal sends them to fix a phone that is not broken.
  final Trouble trouble;

  /// Non-null only when the session could not be settled and there is something to
  /// try again.
  final VoidCallback? onRetry;

  static const _loaderAfter = Duration(milliseconds: 400);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _showLoader = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(SplashScreen._loaderAfter, () {
      if (mounted) setState(() => _showLoader = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stuck = widget.onRetry != null;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: AppColors.white,
        systemNavigationBarColor: AppColors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.white,
        // The Center is load-bearing, and not for centring. Scaffold hands its body
        // *loose* constraints (0 ≤ w ≤ 720), so SafeArea, Padding and a Column whose
        // children all have intrinsic widths every one shrink-wrap, and the whole screen
        // ends up the width of its longest word, at the left edge. Center keeps the
        // bounded width instead of shrink-wrapping it, which is what puts the mark back
        // on the middle of the phone.
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/images/splash_logo.png', width: 116),
                  const SizedBox(height: 20),
                  Text('Communal Meet', style: AppText.display),
                  const SizedBox(height: 6),
                  Text(
                    'Meet your cooperative',
                    textAlign: TextAlign.center,
                    style: AppText.meta,
                  ),
                  const SizedBox(height: 36),
                  if (stuck)
                    SplashTrouble(
                      trouble: widget.trouble,
                      message: widget.message,
                      onRetry: widget.onRetry!,
                    )
                  else
                    SizedBox(
                      height: 3,
                      width: 132,
                      child: AnimatedOpacity(
                        opacity: _showLoader ? 1 : 0,
                        duration: const Duration(milliseconds: 220),
                        child: const ClipRRect(
                          borderRadius: BorderRadius.all(Radius.circular(2)),
                          child: LinearProgressIndicator(
                            minHeight: 3,
                            backgroundColor: AppColors.primarySoft,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The hard stop: a session that cannot be settled, said in the terms the member can
/// act on. It takes the loader's place rather than covering the screen, because unlike
/// the collector's this app has nothing cached to protect — there is simply no way
/// past it until one of the three troubles clears.
class SplashTrouble extends StatelessWidget {
  const SplashTrouble({
    super.key,
    required this.trouble,
    required this.message,
    required this.onRetry,
  });

  final Trouble trouble;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          trouble == Trouble.offline
              ? Icons.signal_wifi_off_rounded
              : Icons.cloud_off_rounded,
          size: 30,
          color: AppColors.primary,
        ),
        const SizedBox(height: 12),
        Text(
          troubleHeading(trouble),
          textAlign: TextAlign.center,
          style: AppText.title,
        ),
        const SizedBox(height: 8),
        Text(
          message.isEmpty ? troubleBody(trouble) : message,
          textAlign: TextAlign.center,
          style: AppText.meta,
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: 200,
          child: FilledButton(
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ),
      ],
    );
  }
}
