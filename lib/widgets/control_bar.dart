import 'package:flutter/material.dart';

import '../core/theme.dart';

/// The bar along the bottom of a meeting. Always dark, whatever the phone's theme —
/// it sits on the stage, and a light bar under a dark stage reads as a different app.
class ControlBar extends StatelessWidget {
  const ControlBar({
    super.key,
    required this.micOn,
    required this.cameraOn,
    required this.sharing,
    required this.handRaised,
    required this.unread,
    required this.canShare,
    required this.onMic,
    required this.onCamera,
    required this.onShare,
    required this.onHand,
    required this.onChat,
    required this.onLeave,
  });

  final bool micOn;
  final bool cameraOn;
  final bool sharing;
  final bool handRaised;
  final int unread;
  final bool canShare;
  final VoidCallback onMic;
  final VoidCallback onCamera;
  final VoidCallback onShare;
  final VoidCallback onHand;
  final VoidCallback onChat;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppStage.bar,
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 10,
        bottom: 10 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Control(
            // The label says what the button does, and the glyph says what is true
            // now. A microphone that is on shows a microphone.
            icon: micOn ? Icons.mic : Icons.mic_off,
            label: micOn ? 'Mute' : 'Unmute',
            danger: !micOn,
            onTap: onMic,
          ),
          _Control(
            icon: cameraOn ? Icons.videocam : Icons.videocam_off,
            label: cameraOn ? 'Camera' : 'Camera',
            danger: !cameraOn,
            onTap: onCamera,
          ),
          if (canShare)
            _Control(
              icon: sharing ? Icons.stop_screen_share : Icons.screen_share,
              label: sharing ? 'Stop' : 'Share',
              active: sharing,
              onTap: onShare,
            ),
          _Control(
            icon: Icons.back_hand_outlined,
            label: 'Hand',
            active: handRaised,
            onTap: onHand,
          ),
          _Control(
            icon: Icons.forum_outlined,
            label: 'Chat',
            badge: unread,
            onTap: onChat,
          ),
          _Control(
            icon: Icons.call_end,
            label: 'Leave',
            danger: true,
            onTap: onLeave,
          ),
        ],
      ),
    );
  }
}

class _Control extends StatelessWidget {
  const _Control({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.active = false,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  final bool active;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final background = danger
        ? AppColors.danger
        : active
        ? AppColors.primary
        : AppStage.tile;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: background,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: danger || active
                            ? Colors.transparent
                            : AppStage.tileLine,
                      ),
                    ),
                    child: Icon(icon, size: 21, color: AppStage.onStage),
                  ),
                  if (badge > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        height: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: AppStage.bar, width: 2),
                        ),
                        child: Text(
                          badge > 9 ? '9+' : '$badge',
                          style: AppText.caption.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: AppText.caption.copyWith(color: AppStage.onStageMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
