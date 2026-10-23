import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/sounds.dart';
import '../core/theme.dart';
import '../data/api_client.dart';
import '../data/models.dart';
import '../data/socket.dart';
import '../state/services.dart';
import '../state/session_cubit.dart';
import '../widgets/participant_tile.dart';
import 'call.dart';

/// The ringing screen. Closes itself when the caller gives up.
class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({super.key, required this.call});

  final CallRecord call;

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  StreamSubscription<SocketFrame>? _frames;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    final services = context.read<AppServices>();
    _frames = services.socket.frames.listen((frame) {
      if (frame.type != 'call.cancelled') return;
      if (frame.str('id') != widget.call.id) return;
      _leave();
    });
    Sounds.ringback();
  }

  @override
  void dispose() {
    _frames?.cancel();
    Sounds.stopRingback();
    super.dispose();
  }

  void _leave() {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  Future<void> _answer() async {
    if (_acting) return;
    setState(() => _acting = true);

    final services = context.read<AppServices>();
    final me = context.read<SessionCubit>().state.caller?.profileId ?? '';

    final wanted = widget.call.video
        ? [Permission.microphone, Permission.camera]
        : [Permission.microphone];
    try {
      final granted = await wanted.request();
      if (!granted.values.every((s) => s.isGranted || s.isLimited)) {
        if (mounted) setState(() => _acting = false);
        return;
      }
    } catch (_) {
      if (mounted) setState(() => _acting = false);
      return;
    }

    CallTicket ticket;
    try {
      ticket = await services.calls.accept(widget.call.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(e.message)));
      _leave();
      return;
    }
    if (!mounted) return;

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            CallScreen(ticket: ticket, outgoing: false, selfProfileId: me),
      ),
    );
  }

  Future<void> _decline() async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await context.read<AppServices>().calls.decline(widget.call.id);
    } on ApiException catch (_) {
      _leave();
      return;
    }
    if (mounted) _leave();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.call.callerName;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppStage.stage,
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              StageAvatar(
                name: name,
                seed: widget.call.callerProfileId,
                size: 128,
              ),
              const SizedBox(height: 24),
              Text(
                name.isEmpty ? 'Unknown caller' : name,
                style: AppText.title.copyWith(color: AppStage.onStage),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                widget.call.video
                    ? 'Incoming video call'
                    : 'Incoming voice call',
                style: AppText.meta.copyWith(color: AppStage.onStageMuted),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 48),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _Answer(
                      icon: Icons.call_end,
                      label: 'Decline',
                      colour: AppColors.danger,
                      onTap: _acting ? null : _decline,
                    ),
                    _Answer(
                      icon: widget.call.video ? Icons.videocam : Icons.call,
                      label: 'Answer',
                      colour: AppColors.success,
                      onTap: _acting ? null : _answer,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Answer extends StatelessWidget {
  const _Answer({
    required this.icon,
    required this.label,
    required this.colour,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color colour;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Semantics(
          button: true,
          label: label,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(40),
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.white, size: 30),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: AppText.meta.copyWith(color: AppStage.onStageMuted)),
      ],
    );
  }
}
