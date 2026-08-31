import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/theme.dart';
import '../data/models.dart';

/// What a knocker sees while a host decides.
///
/// An illustration and not a self-view, deliberately: the green room exists to be looked
/// at, and this screen exists to be waited in. There is nothing here to check — the
/// tracks are prepared and unpublished and nothing reaches the room until admission — so
/// a live camera would only invite somebody to keep fixing their hair instead of telling
/// them the truth, which is that a person is deciding and it takes as long as it takes.
///
/// The mic and camera pills stay, because what you set here is what you join with.
class WaitingRoomView extends StatefulWidget {
  const WaitingRoomView({
    super.key,
    required this.meeting,
    required this.since,
    required this.micOn,
    required this.cameraOn,
    required this.canMic,
    required this.canCamera,
    required this.onMic,
    required this.onCamera,
    required this.onCancel,
  });

  final MeetingSummary meeting;

  /// When the knock landed. The counter only appears once the wait is long enough to
  /// need explaining.
  final DateTime? since;

  final bool micOn;
  final bool cameraOn;
  final bool canMic;
  final bool canCamera;
  final VoidCallback onMic;
  final VoidCallback onCamera;
  final VoidCallback onCancel;

  @override
  State<WaitingRoomView> createState() => _WaitingRoomViewState();
}

class _WaitingRoomViewState extends State<WaitingRoomView> {
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

  String get _elapsed {
    final since = widget.since;
    if (since == null) return '';
    final seconds = DateTime.now().difference(since).inSeconds;
    if (seconds < 30) return '';
    final minutes = seconds ~/ 60;
    return 'Waiting · $minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.meeting.hostName;
    final elapsed = _elapsed;
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const _KnockingDoor(),
                    const SizedBox(height: 28),
                    Text(
                      'Waiting to be let in',
                      textAlign: TextAlign.center,
                      style: AppText.title.copyWith(color: AppStage.onStage),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      host.isEmpty
                          ? 'Someone in the meeting has to let you in.'
                          : '$host has been told you are here.',
                      textAlign: TextAlign.center,
                      style: AppText.meta.copyWith(
                        color: AppStage.onStageMuted,
                      ),
                    ),
                    SizedBox(height: elapsed.isEmpty ? 0 : 16),
                    if (elapsed.isNotEmpty)
                      Text(
                        elapsed,
                        style: AppText.mono.copyWith(
                          color: AppStage.onStageMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _WaitPill(
                icon: widget.micOn ? Icons.mic : Icons.mic_off,
                label: widget.micOn ? 'Mute microphone' : 'Unmute microphone',
                off: !widget.micOn,
                onTap: widget.canMic ? widget.onMic : null,
              ),
              const SizedBox(width: 18),
              _WaitPill(
                icon: widget.cameraOn ? Icons.videocam : Icons.videocam_off,
                label: widget.cameraOn ? 'Turn off camera' : 'Turn on camera',
                off: !widget.cameraOn,
                onTap: widget.canCamera ? widget.onCamera : null,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: widget.onCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppStage.onStage,
                  side: const BorderSide(color: AppStage.tileLine),
                  minimumSize: const Size.fromHeight(50),
                ),
                child: const Text('Cancel'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A closed door with three arcs expanding from its edge.
///
/// `flutter_svg` draws an SVG statically, so the motion is composed here rather than
/// baked into a file nobody could animate: the door is one asset, the ripple is a single
/// arc whose viewBox is symmetric about its own origin, and it is drawn three times on a
/// staggered loop. Three arcs from a door that has not opened is a knock nobody has
/// answered, which is this screen's whole message.
class _KnockingDoor extends StatefulWidget {
  const _KnockingDoor();

  @override
  State<_KnockingDoor> createState() => _KnockingDoorState();
}

class _KnockingDoorState extends State<_KnockingDoor>
    with SingleTickerProviderStateMixin {
  static const _door = Size(240, 200);

  /// Where the arcs come from, in the door's own coordinate space: the right edge, at
  /// the height of the handle.
  static const _origin = Offset(156, 104);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    // Reduce-motion leaves one still arc rather than a door with nothing happening to
    // it: the drawing still reads as a knock, it simply does not move.
    if (!WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
        .disableAnimations) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = _door.width;
    final height = _door.height;
    const ripple = 120.0;
    return SizedBox(
      width: width,
      height: height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Stack(
            children: [
              SvgPicture.asset(
                'assets/images/waiting_room.svg',
                width: width,
                height: height,
              ),
              for (var i = 0; i < 3; i++)
                Positioned(
                  left: _origin.dx - ripple / 2,
                  top: _origin.dy - ripple / 2,
                  child: _Ripple(
                    // 0.8s apart on a 2.4s loop: one arc leaving as the next appears.
                    progress: (_controller.value + i / 3) % 1,
                    size: ripple,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Ripple extends StatelessWidget {
  const _Ripple({required this.progress, required this.size});

  final double progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final eased = Curves.easeOut.transform(progress);
    return Opacity(
      opacity: (0.55 * (1 - eased)).clamp(0.0, 1.0),
      child: Transform.scale(
        scale: 1 + 1.4 * eased,
        child: SvgPicture.asset(
          'assets/images/waiting_room_ripple.svg',
          width: size,
          height: size,
        ),
      ),
    );
  }
}

class _WaitPill extends StatelessWidget {
  const _WaitPill({
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
        borderRadius: BorderRadius.circular(27),
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: off ? AppColors.danger : AppStage.tile,
            shape: BoxShape.circle,
            border: Border.all(
              color: off ? Colors.transparent : AppStage.tileLine,
            ),
          ),
          child: Icon(
            icon,
            size: 22,
            color: onTap == null ? AppStage.onStageMuted : AppStage.onStage,
          ),
        ),
      ),
    );
  }
}
