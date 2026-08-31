import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../state/meeting_cubit.dart';
import '../state/services.dart';
import '../widgets/admission_card.dart';
import '../widgets/control_bar.dart';
import '../widgets/meeting_grid.dart';
import '../widgets/participant_tile.dart';
import '../widgets/participants_sheet.dart';
import '../widgets/stage_chat.dart';
import 'meeting_summary.dart';
import 'waiting_room.dart';

/// The meeting. Everything on this route is dark, including the sheets over it.
class MeetingScreen extends StatelessWidget {
  const MeetingScreen({
    super.key,
    required this.ticket,
    required this.prepared,
    required this.coopName,
    this.hasChat = false,
  });

  final JoinTicket ticket;
  final PreparedMedia prepared;
  final String coopName;

  /// Whether the cooperative has a group chat, so the summary can offer it — the thing
  /// people do after a meeting is talk about it. Opening it is the cooperative's job;
  /// this route cannot reach the conversations cubit.
  final bool hasChat;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => MeetingCubit(
        context.read<AppServices>(),
        ticket: ticket,
        prepared: prepared,
      )..connect(),
      child: _MeetingView(coopName: coopName, hasChat: hasChat),
    );
  }
}

class _MeetingView extends StatefulWidget {
  const _MeetingView({required this.coopName, required this.hasChat});

  final String coopName;
  final bool hasChat;

  @override
  State<_MeetingView> createState() => _MeetingViewState();
}

class _MeetingViewState extends State<_MeetingView> {
  StreamSubscription<String>? _notices;
  bool _sharing = false;

  /// One exit only. The listener fires on every emit after the phase turns, and two of
  /// them would pop the meeting and then the screen behind it.
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _notices = context.read<MeetingCubit>().notices.listen(_say);
  }

  @override
  void dispose() {
    _notices?.cancel();
    if (_sharing) FlutterBackground.disableBackgroundExecution();
    super.dispose();
  }

  void _say(String message) {
    if (message.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ── leaving ────────────────────────────────────────────────────────────────

  Future<void> _confirmLeave() async {
    final cubit = context.read<MeetingCubit>();
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppStage.tile,
      builder: (_) => LeaveSheet(canHost: cubit.state.canHost),
    );
    if (choice == 'leave') {
      await cubit.leave();
    } else if (choice == 'end') {
      _say(await cubit.endForEveryone());
    }
  }

  Future<void> _onOver(MeetingState state) async {
    if (_left) return;
    _left = true;

    // A refusal and a failed join both belong back where they started, with a sentence
    // and no retry button — a retry on a denial is an invitation to knock again. There
    // is nothing to summarise either: nobody was in a meeting.
    if (state.phase == MeetingPhase.denied ||
        state.phase == MeetingPhase.failed) {
      Navigator.of(context).pop(MeetingExit(message: state.message));
      return;
    }

    final exit = await Navigator.of(context).push<MeetingExit>(
      MaterialPageRoute(
        builder: (_) => MeetingSummaryScreen(
          meeting: state.meeting,
          coopName: widget.coopName,
          message: state.message,
          duration: state.connectedAt == null
              ? null
              : DateTime.now().difference(state.connectedAt!),
          hasChat: widget.hasChat,
          wasHost: state.canHost,
        ),
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop(exit ?? const MeetingExit());
  }

  // ── the controls ───────────────────────────────────────────────────────────

  Future<void> _openChat() async {
    final cubit = context.read<MeetingCubit>();
    cubit.chatOpened();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: const StageChatSheet(),
      ),
    );
    cubit.chatClosed();
  }

  Future<void> _openPeople() async {
    final cubit = context.read<MeetingCubit>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: const ParticipantsSheet(),
      ),
    );
  }

  /// Screen sharing, and the Android service that has to be running for it.
  ///
  /// The capture permission and the `mediaProjection` foreground service are asked for
  /// here rather than in the cubit, because the service posts a notification the member
  /// can see and a state holder has no business posting one.
  Future<void> _share() async {
    final cubit = context.read<MeetingCubit>();
    final stopping = cubit.state.screenSharing;

    if (!stopping && Platform.isAndroid && !await _startCaptureService()) {
      _say('This phone would not let us share its screen.');
      return;
    }

    final trouble = await cubit.toggleScreenShare();
    if (trouble.isNotEmpty) {
      _say(trouble);
    }
    final sharing = cubit.state.screenSharing;
    if (Platform.isAndroid && !sharing && _sharing) {
      await FlutterBackground.disableBackgroundExecution();
    }
    _sharing = sharing;
  }

  Future<bool> _startCaptureService() async {
    try {
      if (!await Hardware.instance.requestCapturePermission()) return false;
      final started = await FlutterBackground.initialize(
        androidConfig: const FlutterBackgroundAndroidConfig(
          notificationTitle: 'Sharing your screen',
          notificationText: 'Everyone in the meeting can see this phone.',
          notificationIcon: AndroidResource(name: 'brand_mark_white'),
          // Battery-optimisation exemption is a second dialog for a permission this
          // app does not declare, and the share only has to last the meeting.
          shouldRequestBatteryOptimizationsOff: false,
        ),
      );
      if (!started) return false;
      return await FlutterBackground.enableBackgroundExecution();
    } catch (_) {
      return false;
    }
  }

  Future<void> _hostMenu() async {
    final cubit = context.read<MeetingCubit>();
    final state = cubit.state;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppStage.tile,
      builder: (_) => _HostMenu(
        canHost: state.canHost,
        recording: state.recording,
      ),
    );
    if (!mounted || choice == null) return;

    switch (choice) {
      case 'people':
        await _openPeople();
      case 'record':
        _say(await cubit.setRecording(!state.recording));
      case 'mute_all':
        _say(await cubit.mute());
      case 'end':
        final sure = await showModalBottomSheet<bool>(
          context: context,
          backgroundColor: AppStage.tile,
          builder: (_) => const StageConfirm(
            title: 'End the meeting for everyone?',
            body: 'Everybody is disconnected. A recording that is running is '
                'finalised and kept.',
            action: 'End meeting',
          ),
        );
        if (sure == true) _say(await cubit.endForEveryone());
    }
  }

  // ── the screen ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<MeetingCubit>();
    return BlocConsumer<MeetingCubit, MeetingState>(
      listenWhen: (a, b) => a.phase != b.phase,
      listener: (context, state) {
        if (state.isOver) _onOver(state);
      },
      builder: (context, state) {
        return PopScope(
          // The system back gesture must not drop a member out of a meeting silently.
          canPop: state.isOver,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !state.isOver) _confirmLeave();
          },
          child: Scaffold(
            backgroundColor: AppStage.stage,
            body: _body(context, state, cubit),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, MeetingState state, MeetingCubit cubit) {
    if (state.phase == MeetingPhase.waiting) {
      return WaitingRoomView(
        meeting: state.meeting,
        since: state.connectedAt,
        micOn: state.micOn,
        cameraOn: state.cameraOn,
        canMic: cubit.canToggleMic,
        canCamera: cubit.canToggleCamera,
        onMic: cubit.toggleMic,
        onCamera: cubit.toggleCamera,
        onCancel: cubit.leave,
      );
    }
    if (state.phase == MeetingPhase.connecting || state.isOver) {
      return SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 20),
              Text(
                state.isOver
                    ? 'Leaving…'
                    : 'Joining ${widget.coopName.isEmpty ? 'the meeting' : widget.coopName}…',
                style: AppText.meta.copyWith(color: AppStage.onStageMuted),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          _TopBar(
            title: widget.coopName.isEmpty
                ? state.meeting.displayTitle
                : widget.coopName,
            recording: state.recording,
            connectedAt: state.connectedAt,
            onMenu: _hostMenu,
          ),
          if (state.phase == MeetingPhase.reconnecting)
            const _Strip(
              label: 'Reconnecting',
              colour: AppColors.warning,
              background: AppColors.warningSoft,
            )
          else if (state.unstable)
            const _Strip(
              label: 'Your connection is unstable',
              colour: AppColors.warning,
              background: AppColors.warningSoft,
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: _stage(state),
            ),
          ),
          if (state.canHost && state.waiting.isNotEmpty)
            AdmissionCard(
              waiting: state.waiting,
              onDecide: (who, admit) async {
                _say(await cubit.decide(who, admit: admit));
              },
              onAdmitAll: cubit.admitAll,
            ),
          ControlBar(
            micOn: state.micOn,
            cameraOn: state.cameraOn,
            sharing: state.screenSharing,
            handRaised: state.handRaised,
            unread: state.unreadChat,
            canShare: !state.meeting.isCall,
            onMic: cubit.toggleMic,
            onCamera: cubit.toggleCamera,
            onShare: _share,
            onHand: cubit.toggleHand,
            onChat: _openChat,
            onLeave: _confirmLeave,
          ),
        ],
      ),
    );
  }

  Widget _stage(MeetingState state) {
    final share = state.screenShare;
    if (share != null) {
      return Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                color: AppStage.tile,
                child: VideoTrackRenderer(share, fit: VideoViewFit.contain),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              state.screenShareBy.isEmpty
                  ? 'Someone is sharing their screen'
                  : '${state.screenShareBy} is sharing their screen',
              style: AppText.caption.copyWith(color: AppStage.onStageMuted),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: state.people.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => SizedBox(
                width: 120,
                child: ParticipantTile(tile: state.people[i], radius: 10),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Expanded(child: MeetingGrid(people: state.people)),
        if (state.alone)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Waiting for others to join',
              style: AppText.meta.copyWith(color: AppStage.onStageMuted),
            ),
          ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.recording,
    required this.connectedAt,
    required this.onMenu,
  });

  final String title;
  final bool recording;
  final DateTime? connectedAt;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 14, right: 4, top: 6, bottom: 2),
      child: Row(
        children: [
          if (recording) ...[
            const _RecDot(),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.subtitle.copyWith(color: AppStage.onStage),
            ),
          ),
          const SizedBox(width: 8),
          _Clock(since: connectedAt),
          IconButton(
            tooltip: 'More',
            onPressed: onMenu,
            icon: const Icon(Icons.more_vert, color: AppStage.onStage),
          ),
        ],
      ),
    );
  }
}

/// The word as well as the dot, because nothing in this app depends on colour alone.
class _RecDot extends StatelessWidget {
  const _RecDot();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: AppStage.live,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          'REC',
          style: AppText.caption.copyWith(
            color: AppStage.live,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// How long this member has been in the meeting. Its own widget with its own timer, so
/// one second of clock does not rebuild a grid of decoders.
class _Clock extends StatefulWidget {
  const _Clock({required this.since});

  final DateTime? since;

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final since = widget.since;
    if (since == null) return const SizedBox.shrink();
    return Text(
      elapsedLabel(DateTime.now().difference(since)),
      style: AppText.mono.copyWith(
        color: AppStage.onStageMuted,
        fontSize: 14,
      ),
    );
  }
}

/// `12:04`, and `1:02:04` once a meeting has been going for an hour.
String elapsedLabel(Duration d) {
  final seconds = d.inSeconds < 0 ? 0 : d.inSeconds;
  final minutes = (seconds ~/ 60) % 60;
  final hours = seconds ~/ 3600;
  final tail =
      '${minutes.toString().padLeft(2, '0')}:'
      '${(seconds % 60).toString().padLeft(2, '0')}';
  return hours > 0 ? '$hours:$tail' : tail;
}

class _Strip extends StatelessWidget {
  const _Strip({
    required this.label,
    required this.colour,
    required this.background,
  });

  final String label;
  final Color colour;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: AppText.caption.copyWith(color: colour),
      ),
    );
  }
}

class _HostMenu extends StatelessWidget {
  const _HostMenu({required this.canHost, required this.recording});

  final bool canHost;
  final bool recording;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          _Item(
            icon: Icons.people_outline,
            label: 'Participants',
            onTap: () => Navigator.of(context).pop('people'),
          ),
          if (canHost) ...[
            _Item(
              icon: recording
                  ? Icons.stop_circle_outlined
                  : Icons.fiber_manual_record_outlined,
              label: recording ? 'Stop recording' : 'Record this meeting',
              onTap: () => Navigator.of(context).pop('record'),
            ),
            _Item(
              icon: Icons.mic_off_outlined,
              label: 'Mute everyone',
              onTap: () => Navigator.of(context).pop('mute_all'),
            ),
            _Item(
              icon: Icons.call_end,
              label: 'End meeting for everyone',
              danger: true,
              onTap: () => Navigator.of(context).pop('end'),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colour = danger ? AppStage.live : AppStage.onStage;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: colour, size: 21),
      title: Text(label, style: AppText.body.copyWith(color: colour)),
    );
  }
}
