import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../data/api_client.dart';
import '../data/repositories.dart';
import '../state/services.dart';
import '../state/session_cubit.dart';

enum _Step { identify, pin, takeover }

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.notice = ''});

  final String notice;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _login = TextEditingController();
  final _pin = TextEditingController();
  final _otp = TextEditingController();

  _Step _step = _Step.identify;
  bool _busy = false;
  bool _showPin = false;
  String _error = '';
  String _hint = '';
  String _challengeId = '';

  @override
  void initState() {
    super.initState();
    _hint = widget.notice;
  }

  @override
  void dispose() {
    _login.dispose();
    _pin.dispose();
    _otp.dispose();
    super.dispose();
  }

  AppServices get _services => context.read<AppServices>();

  Future<void> _run(Future<void> Function() body) async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await body();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _identify() => _run(() async {
    final login = _login.text.trim();
    if (login.isEmpty) {
      setState(() => _error = 'Enter your phone number or email.');
      return;
    }
    final check = await _services.auth.check(login);
    if (!mounted) return;
    if (!check.hasPassword || check.needsOtp) {
      setState(
        () => _error =
            'This account has no PIN yet. Set one in the Communal app, '
            'then sign in here.',
      );
      return;
    }
    setState(() {
      _step = _Step.pin;
      _hint = '';
    });
  });

  Future<void> _signIn() => _run(() async {
    final pin = _pin.text.trim();
    if (pin.length != AppConfig.pinLength) {
      setState(() => _error = 'Your PIN is ${AppConfig.pinLength} digits.');
      return;
    }
    final result = await _services.auth.signIn(_login.text.trim(), pin);
    if (!mounted) return;
    if (result.needsTakeoverOtp) {
      setState(() {
        _step = _Step.takeover;
        _challengeId = result.takeoverChallengeId;
        _hint = result.maskedDestination.isEmpty
            ? 'You are signed in on another device. We sent you a code.'
            : 'You are signed in on another device. '
                  'We sent a code to ${result.maskedDestination}.';
      });
      return;
    }
    await _adopt(result);
  });

  Future<void> _verifyTakeover() => _run(() async {
    final otp = _otp.text.trim();
    if (otp.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    final result = await _services.auth.verifyTakeover(
      challengeId: _challengeId,
      otp: otp,
    );
    await _adopt(result);
  });

  Future<void> _resend() => _run(() async {
    final to = await _services.auth.resendTakeoverOtp(_challengeId);
    if (!mounted) return;
    setState(
      () => _hint = to.isEmpty ? 'We sent a new code.' : 'New code sent to $to.',
    );
  });

  Future<void> _adopt(SignInResult result) async {
    if (!result.signedIn) {
      if (mounted) setState(() => _error = 'That sign-in did not complete.');
      return;
    }
    await context.read<SessionCubit>().adopt(
      token: result.token,
      refreshToken: result.refreshToken,
    );
  }

  void _back() {
    setState(() {
      _step = _Step.identify;
      _error = '';
      _hint = '';
      _pin.clear();
      _otp.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: _step == _Step.identify
          ? null
          : AppBar(
              leading: IconButton(
                onPressed: _busy ? null : _back,
                icon: const Icon(Icons.arrow_back),
              ),
            ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_step == _Step.identify) const SizedBox(height: 28),
              Image.asset('assets/images/mark_purple.png', width: 64),
              const SizedBox(height: 20),
              Text(_headline, style: AppText.display),
              const SizedBox(height: 8),
              Text(_blurb, style: AppText.meta),
              const SizedBox(height: 24),
              ..._fields(),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 14),
                _Notice(text: _error, danger: true),
              ],
              if (_error.isEmpty && _hint.isNotEmpty) ...[
                const SizedBox(height: 14),
                _Notice(text: _hint),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _primary,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: AppColors.white,
                        ),
                      )
                    : Text(_cta),
              ),
              if (_step == _Step.takeover)
                TextButton(
                  onPressed: _busy ? null : _resend,
                  child: const Text('Send a new code'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String get _headline {
    switch (_step) {
      case _Step.identify:
        return 'Meet your cooperative';
      case _Step.pin:
        return 'Enter your PIN';
      case _Step.takeover:
        return 'Confirm it is you';
    }
  }

  String get _blurb {
    switch (_step) {
      case _Step.identify:
        return 'Sign in with the phone number or email your cooperative '
            'has on file.';
      case _Step.pin:
        return 'The same ${AppConfig.pinLength}-digit PIN you use on '
            'Communal.';
      case _Step.takeover:
        return 'Signing in here ends your session on the other device.';
    }
  }

  String get _cta {
    switch (_step) {
      case _Step.identify:
        return 'Continue';
      case _Step.pin:
        return 'Sign in';
      case _Step.takeover:
        return 'Confirm';
    }
  }

  VoidCallback get _primary {
    switch (_step) {
      case _Step.identify:
        return _identify;
      case _Step.pin:
        return _signIn;
      case _Step.takeover:
        return _verifyTakeover;
    }
  }

  List<Widget> _fields() {
    switch (_step) {
      case _Step.identify:
        return [
          TextField(
            controller: _login,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _busy ? null : _identify(),
            style: AppText.body,
            decoration: const InputDecoration(
              hintText: 'Phone number or email',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
        ];
      case _Step.pin:
        return [
          Text(_login.text.trim(), style: AppText.subtitle),
          const SizedBox(height: 12),
          TextField(
            controller: _pin,
            autofocus: true,
            obscureText: !_showPin,
            keyboardType: TextInputType.number,
            maxLength: AppConfig.pinLength,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _busy ? null : _signIn(),
            style: AppText.mono.copyWith(fontSize: 22, letterSpacing: 10),
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••••',
              hintStyle: AppText.mono.copyWith(
                fontSize: 22,
                letterSpacing: 10,
                color: AppColors.line,
              ),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _showPin = !_showPin),
                icon: Icon(
                  _showPin ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.muted,
                ),
              ),
            ),
          ),
        ];
      case _Step.takeover:
        return [
          TextField(
            controller: _otp,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _busy ? null : _verifyTakeover(),
            style: AppText.mono.copyWith(fontSize: 22, letterSpacing: 10),
            decoration: const InputDecoration(
              counterText: '',
              hintText: '------',
            ),
          ),
        ];
    }
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: danger ? AppColors.dangerSoft : AppColors.primarySoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            danger ? Icons.error_outline : Icons.info_outline,
            size: 17,
            color: danger ? AppColors.danger : AppColors.primaryDark,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppText.meta.copyWith(
                color: danger ? AppColors.danger : AppColors.primaryDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
