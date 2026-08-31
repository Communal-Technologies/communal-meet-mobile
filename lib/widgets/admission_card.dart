import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import 'participant_tile.dart';

/// Who is knocking, shown to a host at the bottom of the stage.
///
/// A card and not a dialog: a knock arrives mid-sentence, and something that steals
/// focus to announce a person who is not in the meeting yet interrupts the meeting it is
/// interrupting for. **Nothing is pre-selected and neither action is the default** —
/// an accidental admit puts an unapproved person into a room that may be recording.
class AdmissionCard extends StatelessWidget {
  const AdmissionCard({
    super.key,
    required this.waiting,
    required this.onDecide,
    required this.onAdmitAll,
  });

  final List<MeetingAttendee> waiting;
  final void Function(MeetingAttendee who, bool admit) onDecide;
  final VoidCallback onAdmitAll;

  @override
  Widget build(BuildContext context) {
    if (waiting.isEmpty) return const SizedBox.shrink();
    final first = waiting.first;
    final others = waiting.length - 1;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppStage.tile,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppStage.tileLine),
        boxShadow: [
          // There is no hairline that reads against moving video.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 24,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StageAvatar(
                name: first.name,
                seed: first.profileId,
                size: 38,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      first.name.isEmpty ? 'Someone' : first.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.subtitle.copyWith(
                        color: AppStage.onStage,
                      ),
                    ),
                    Text(
                      others > 0
                          ? 'wants to join · ${countLabel(others, 'other is', 'others are')} waiting'
                          : 'wants to join',
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => onDecide(first, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppStage.onStage,
                    side: const BorderSide(color: AppStage.tileLine),
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: const Text('Deny'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => onDecide(first, true),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: const Text('Admit'),
                ),
              ),
            ],
          ),
          if (others > 0)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onAdmitAll,
                child: Text('Admit all ${waiting.length}'),
              ),
            ),
        ],
      ),
    );
  }
}
