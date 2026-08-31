import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../state/meeting_cubit.dart';

/// One person on the stage.
///
/// The camera when there is one, initials when there is not — and an audio meeting is
/// mostly initials, so the avatar tile is the one that has to look deliberate rather
/// than like a video that failed to arrive.
class ParticipantTile extends StatelessWidget {
  const ParticipantTile({
    super.key,
    required this.tile,
    this.radius = 14,
    this.fit = VideoViewFit.cover,
    this.showName = true,
  });

  final MeetingTile tile;
  final double radius;
  final VideoViewFit fit;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final video = tile.video;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppStage.tile,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: tile.speaking ? AppStage.speaking : AppStage.tileLine,
          width: tile.speaking ? 2 : 1,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (video != null && tile.cameraOn)
            VideoTrackRenderer(video, fit: fit)
          else
            Center(child: StageAvatar(name: tile.name, seed: tile.identity)),
          if (tile.handRaised)
            const Positioned(
              top: 6,
              right: 6,
              child: _Glyph(
                icon: Icons.back_hand,
                background: AppColors.primary,
              ),
            ),
          if (tile.weak)
            Positioned(
              top: 6,
              left: 6,
              child: _Glyph(
                icon: Icons.network_check,
                background: AppColors.warning.withValues(alpha: 0.9),
              ),
            ),
          if (showName)
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: Row(
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!tile.micOn) ...[
                            const Icon(
                              Icons.mic_off,
                              size: 13,
                              color: AppStage.onStage,
                            ),
                            const SizedBox(width: 5),
                          ],
                          Flexible(
                            child: Text(
                              tile.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.caption.copyWith(
                                color: AppStage.onStage,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Initials on the dark stage. The light-surface [AppAvatar] cannot be reused here —
/// its tints are chosen against white and disappear against near-black.
class StageAvatar extends StatelessWidget {
  const StageAvatar({
    super.key,
    required this.name,
    required this.seed,
    this.size = 56,
  });

  final String name;
  final String seed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colour = hueFor(seed);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color.alphaBlend(colour.withValues(alpha: 0.42), AppStage.tile),
        shape: BoxShape.circle,
      ),
      child: Text(
        initials(name),
        style: AppText.subtitle.copyWith(
          color: AppStage.onStage,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon, required this.background});

  final IconData icon;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(icon, size: 14, color: AppColors.white),
    );
  }
}
