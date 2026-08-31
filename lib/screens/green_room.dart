import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/theme.dart';
import '../data/api_client.dart';
import '../data/models.dart';
import '../state/meeting_cubit.dart';
import '../state/services.dart';
import '../widgets/participant_tile.dart';
import 'meeting.dart';

/// The screen before the meeting: see yourself, set your microphone and camera, then
/// go in.
///
/// Two things are load-bearing here. The tracks are acquired **before** the join call,
/// so a slow backend does not stall the preview — and they are then handed to the
/// meeting rather than re-created, so what a member set here is what they join with.
/// From the hand-off on, this screen owns nothing: two owners stopping one track is a
/// dead publication.
class GreenRoomScreen extends StatefulWidget {
  const GreenRoomScreen({super.key, required this.space, this.meeting});

  final Space space;

  /// The meeting to join. Null means the host is opening one, and it is created when
  /// they press the button — not before, or a member who changed their mind would leave
  /// a live meeting behind them.
  final MeetingSummary? meeting;

  @override
  State<GreenRoomScreen> createState() => _GreenRoomScreenState();
}

enum _Stage { acquiring, ready, joining }

class _GreenRoomScreenState extends State<GreenRoomScreen> {
  _Stage _stage = _Stage.acquiring;

  LocalAudioTrack? _audio;
  LocalVideoTrack? _video;
  bool _micOn = true;
  bool _cameraOn = true;
  bool _front = true;
  bool _speaker = true;
  bool _handedOver = false;

  /// What could not be had, and why — the sentence goes where the video would be.
  String _micTrouble = '';
  String _cameraTrouble = '';
  bool _settingsHelps = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    if (!_handedOver) {
      // Not handed over: nobody else will stop these.
      _audio?.stop();
      _video?.stop();
    }
    super.dispose();
  }

  /// Microphone first, camera second, per the order the app asks for anything —
  /// and a refusal of either is not a dead end. A member who cannot be heard can
  /// still listen to their cooperative's AGM, which is most of what an AGM is.
  Future<void> _prepare() async {
    final mic = await Permission.microphone.request();
    if (mic.isGranted) {
      try {
        _audio = await LocalAudioTrack.create();
      } catch (_) {
        _micTrouble = 'We could not open the microphone on this phone.';
      }
    } else {
      _micTrouble = 'Communal Meet cannot hear your microphone. '
          'You can still join and listen.';
      _settingsHelps = _settingsHelps || mic.isPermanentlyDenied;
    }

    final camera = await Permission.camera.request();
    if (camera.isGranted) {
      try {
        _video = await LocalVideoTrack.createCameraTrack(
          const CameraCaptureOptions(cameraPosition: CameraPosition.front),
        );
      } catch (_) {
        _cameraTrouble = 'This phone would not give us its camera.';
      }
    } else {
      _cameraTrouble = 'Communal Meet cannot see your camera. '
          'You can still join with audio only.';
      _settingsHelps = _settingsHelps || camera.isPermanentlyDenied;
    }

    if (_audio == null) _micOn = false;
    if (_video == null) _cameraOn = false;
    try {
      await AudioManager.instance.setSpeakerOutputPreferred(_speaker);
    } catch (_) {
      // The route is a preference, not a requirement.
    }

    if (!mounted) return;
    setState(() => _stage = _Stage.ready);
  }

  /// Mutes rather than stops: [LocalTrack.mute] closes the capturer by default, and a
  /// stopped track that is then published is a black rectangle with a live name on it.
  Future<void> _toggleMic() async {
    final track = _audio;
    if (track == null) return;
    final want = !_micOn;
    setState(() => _micOn = want);
    try {
      if (want) {
        await track.unmute(stopOnMute: false);
      } else {
        await track.mute(stopOnMute: false);
      }
    } catch (_) {
      if (mounted) setState(() => _micOn = !want);
    }
  }

  Future<void> _toggleCamera() async {
    final track = _video;
    if (track == null) return;
    final want = !_cameraOn;
    setState(() => _cameraOn = want);
    try {
      if (want) {
        await track.unmute(stopOnMute: false);
      } else {
        await track.mute(stopOnMute: false);
      }
    } catch (_) {
      if (mounted) setState(() => _cameraOn = !want);
    }
  }

  Future<void> _flipCamera() async {
    final track = _video;
    if (track == null) return;
    final front = !_front;
    setState(() => _front = front);
    try {
      await track.setCameraPosition(
        front ? CameraPosition.front : CameraPosition.back,
      );
    } catch (_) {
      if (mounted) setState(() => _front = !front);
    }
  }

  Future<void> _toggleSpeaker() async {
    final want = !_speaker;
    setState(() => _speaker = want);
    try {
      await AudioManager.instance.setSpeakerOutputPreferred(want);
    } catch (_) {
      if (mounted) setState(() => _speaker = !want);
    }
  }

  Future<void> _join() async {
    if (_stage == _Stage.joining) return;
    setState(() {
      _stage = _Stage.joining;
      _error = '';
    });

    final services = context.read<AppServices>();
    try {
      var meeting = widget.meeting;
      meeting ??= await services.meetings.create(
        cooperativeId: widget.space.cooperativeId,
        title: '',
      );
      final ticket = await services.meetings.join(meeting.id);
      if (!mounted) return;

      final prepared = PreparedMedia(
        audio: _audio,
        video: _video,
        micOn: _micOn,
        cameraOn: _cameraOn,
      );
      // From here the meeting owns the tracks. Ownership passes before the push so an
      // exception on the way in cannot leave both screens believing they hold them.
      _handedOver = true;
      _audio = null;
      _video = null;

      final exit = await Navigator.of(context).push<MeetingExit>(
        MaterialPageRoute(
          builder: (_) => MeetingScreen(
            ticket: ticket,
            prepared: prepared,
            coopName: widget.space.cooperativeName,
            hasChat: widget.space.conversation != null,
          ),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(exit ?? const MeetingExit());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.ready;
        _error = e.message;
      });
    }
  }

  /// "Ask to join" is the only warning a member gets that pressing this leads to a
  /// wait, so it has to be right: a host is never held in a lobby, and a meeting with
  /// no lobby holds nobody.
  String get _action {
    if (widget.meeting == null) return 'Start meeting';
    final lobby = widget.meeting!.lobbyEnabled && !widget.space.canHost;
    return lobby ? 'Ask to join' : 'Join now';
  }

  @override
  Widget build(BuildContext context) {
    final meeting = widget.meeting;
    final others = (meeting?.participantCount ?? 0);
    final joining = _stage == _Stage.joining;

    return Scaffold(
      backgroundColor: AppStage.stage,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 16, top: 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close',
                    onPressed: joining ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: AppStage.onStage),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          widget.space.cooperativeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: AppText.subtitle.copyWith(
                            color: AppStage.onStage,
                          ),
                        ),
                        if (meeting != null && meeting.title.isNotEmpty)
                          Text(
                            meeting.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(
                              color: AppStage.onStageMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _preview(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (others > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        others == 1
                            ? '1 other is here'
                            : '$others others are here',
                        style: AppText.meta.copyWith(
                          color: AppStage.onStageMuted,
                        ),
                      ),
                    ),
                  if (_video != null)
                    _SettingRow(
                      label: 'Camera',
                      value: _front ? 'Front' : 'Back',
                      icon: Icons.cameraswitch_outlined,
                      onTap: joining ? null : _flipCamera,
                    ),
                  _SettingRow(
                    label: 'Sound',
                    value: _speaker ? 'Speaker' : 'Earpiece',
                    icon: _speaker ? Icons.volume_up : Icons.hearing,
                    onTap: joining ? null : _toggleSpeaker,
                  ),
                  if (_settingsHelps) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: openAppSettings,
                        child: const Text('Open settings'),
                      ),
                    ),
                  ],
                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error,
                      style: AppText.meta.copyWith(color: AppStage.live),
                    ),
                  ],
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: _stage == _Stage.ready ? _join : null,
                    child: joining
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.white,
                            ),
                          )
                        : Text(_action),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview() {
    final video = _video;
    final me = context.read<AppServices>().session.caller?.name ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        color: AppStage.tile,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_stage == _Stage.acquiring)
              const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            else if (video != null && _cameraOn)
              VideoTrackRenderer(video, fit: VideoViewFit.cover)
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StageAvatar(name: me, seed: me, size: 76),
                    if (_cameraTrouble.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Text(
                          _cameraTrouble,
                          textAlign: TextAlign.center,
                          style: AppText.meta.copyWith(
                            color: AppStage.onStageMuted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            if (_micTrouble.isNotEmpty)
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _micTrouble,
                    style: AppText.caption.copyWith(color: AppStage.onStage),
                  ),
                ),
              ),
            if (_stage != _Stage.acquiring)
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Pill(
                      icon: _micOn ? Icons.mic : Icons.mic_off,
                      label: _micOn ? 'Mute microphone' : 'Unmute microphone',
                      off: !_micOn,
                      onTap: _audio == null ? null : _toggleMic,
                    ),
                    const SizedBox(width: 18),
                    _Pill(
                      icon: _cameraOn ? Icons.videocam : Icons.videocam_off,
                      label: _cameraOn ? 'Turn off camera' : 'Turn on camera',
                      off: !_cameraOn,
                      onTap: _video == null ? null : _toggleCamera,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.off,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool off;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: 54,
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: off
                ? AppColors.danger
                : Colors.black.withValues(alpha: 0.55),
            shape: BoxShape.circle,
            border: Border.all(
              color: off ? Colors.transparent : AppStage.tileLine,
            ),
          ),
          child: Icon(
            icon,
            size: 23,
            color: onTap == null ? AppStage.onStageMuted : AppStage.onStage,
          ),
        ),
      ),
    );
  }
}

/// A row from the column below the video: a label, what it is set to, and one tap that
/// changes it. There is no picker because there is nothing to pick from — a phone has
/// one microphone as far as the platform will admit, and its own choice of route is
/// better than a list of two.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 19, color: AppStage.onStageMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: AppText.body.copyWith(color: AppStage.onStage),
              ),
            ),
            Text(
              value,
              style: AppText.body.copyWith(color: AppStage.onStageMuted),
            ),
            const Icon(
              Icons.expand_more,
              size: 18,
              color: AppStage.onStageMuted,
            ),
          ],
        ),
      ),
    );
  }
}
