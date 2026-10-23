import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/call_cubit.dart';
import '../state/services.dart';
import '../widgets/participant_tile.dart';

/// A 1:1 call: the other person full-bleed, yourself in the corner.
class CallScreen extends StatelessWidget {
  const CallScreen({
    super.key,
    required this.ticket,
    required this.outgoing,
    required this.selfProfileId,
  });

  final CallTicket ticket;
  final bool outgoing;
  final String selfProfileId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          CallCubit(context.read<AppServices>(), ticket, outgoing: outgoing)
            ..start(),
      child: _CallView(selfProfileId: selfProfileId),
    );
  }
}

class _CallView extends StatelessWidget {
  const _CallView({required this.selfProfileId});

  final String selfProfileId;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CallCubit, CallState>(
      listenWhen: (before, after) => !before.isOver && after.isOver,
      listener: (context, state) async {
        final messenger = ScaffoldMessenger.maybeOf(context);
        final navigator = Navigator.of(context);
        if (state.notice.isNotEmpty) {
          messenger?.showSnackBar(SnackBar(content: Text(state.notice)));
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (navigator.canPop()) navigator.pop();
      },
      builder: (context, state) {
        final name = state.call.otherName(selfProfileId);
        final video = _remoteVideo(state.remote);
        return PopScope(
          canPop: state.isOver,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) context.read<CallCubit>().hangUp();
          },
          child: Scaffold(
            backgroundColor: AppStage.stage,
            body: Stack(
              fit: StackFit.expand,
              children: [
                if (video != null)
                  VideoTrackRenderer(video, fit: VideoViewFit.cover)
                else
                  Center(
                    child: StageAvatar(
                      name: name,
                      seed: state.call.otherProfileId(selfProfileId),
                      size: 112,
                    ),
                  ),
                _Scrim(),
                SafeArea(
                  child: Column(
                    children: [
                      _Header(name: name, state: state),
                      const Spacer(),
                      if (state.cameraOn && state.local != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              right: 16,
                              bottom: 12,
                            ),
                            child: _SelfView(local: state.local!),
                          ),
                        ),
                      _Controls(state: state),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  VideoTrack? _remoteVideo(RemoteParticipant? remote) {
    if (remote == null) return null;
    for (final publication in remote.videoTrackPublications) {
      final track = publication.track;
      if (track is VideoTrack && publication.subscribed && !publication.muted) {
        return track;
      }
    }
    return null;
  }
}

class _Scrim extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x99000000), Color(0x00000000), Color(0xB3000000)],
        stops: [0, 0.4, 1],
      ),
    ),
    child: SizedBox.expand(),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.state});

  final String name;
  final CallState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        children: [
          Text(
            name.isEmpty ? 'Call' : name,
            style: AppText.title.copyWith(color: AppStage.onStage),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            _status(state),
            style: AppText.meta.copyWith(color: AppStage.onStageMuted),
          ),
        ],
      ),
    );
  }

  String _status(CallState state) {
    switch (state.phase) {
      case CallPhase.ringing:
        return 'Ringing…';
      case CallPhase.connecting:
        return 'Connecting…';
      case CallPhase.live:
        return callDuration(state.seconds);
      case CallPhase.ended:
        return 'Call ended';
      case CallPhase.failed:
        return 'Could not connect';
    }
  }
}

class _SelfView extends StatelessWidget {
  const _SelfView({required this.local});

  final LocalParticipant local;

  @override
  Widget build(BuildContext context) {
    VideoTrack? track;
    for (final publication in local.videoTrackPublications) {
      final candidate = publication.track;
      if (candidate is VideoTrack && !publication.muted) {
        track = candidate;
        break;
      }
    }
    if (track == null) return const SizedBox.shrink();
    return Container(
      width: 104,
      height: 150,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppStage.tile,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppStage.tileLine),
      ),
      child: VideoTrackRenderer(track, fit: VideoViewFit.cover),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.state});

  final CallState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CallCubit>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CallButton(
            icon: state.micOn ? Icons.mic : Icons.mic_off,
            label: state.micOn ? 'Mute' : 'Unmute',
            onTap: cubit.toggleMic,
          ),
          if (state.call.video)
            _CallButton(
              icon: state.cameraOn ? Icons.videocam : Icons.videocam_off,
              label: state.cameraOn ? 'Camera' : 'Camera off',
              onTap: cubit.toggleCamera,
            ),
          _CallButton(
            icon: state.speakerOn ? Icons.volume_up : Icons.hearing,
            label: state.speakerOn ? 'Speaker' : 'Earpiece',
            onTap: cubit.toggleSpeaker,
          ),
          _CallButton(
            icon: Icons.call_end,
            label: 'End',
            background: AppColors.danger,
            onTap: cubit.hangUp,
          ),
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.background,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(32),
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: background ?? AppStage.tile,
            shape: BoxShape.circle,
            border: Border.all(color: AppStage.tileLine),
          ),
          child: Icon(icon, color: AppStage.onStage, size: 24),
        ),
      ),
    );
  }
}
