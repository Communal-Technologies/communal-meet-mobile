import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/conversations_cubit.dart';
import '../state/spaces_cubit.dart';
import '../widgets/states.dart';
import 'chats_tab.dart';
import 'green_room.dart';

class CoopsTab extends StatelessWidget {
  const CoopsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SpacesCubit>();
    return BlocBuilder<SpacesCubit, SpacesState>(
      builder: (context, state) {
        if (state.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.items.isEmpty && state.error.isNotEmpty) {
          return FailureState(
            message: state.error,
            trouble: state.trouble,
            onRetry: cubit.load,
          );
        }
        if (state.items.isEmpty) {
          return const EmptyState(
            asset: 'empty_coops.svg',
            title: 'You are not in a cooperative yet',
            body: 'Join one in the Wallet app and its group chat and '
                'meetings appear here.',
          );
        }
        return RefreshIndicator(
          onRefresh: cubit.load,
          color: AppColors.primary,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: state.items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _SpaceCard(space: state.items[i]),
          ),
        );
      },
    );
  }
}

class _SpaceCard extends StatelessWidget {
  const _SpaceCard({required this.space});

  final Space space;

  @override
  Widget build(BuildContext context) {
    final live = space.liveMeeting;
    final next = space.nextMeeting;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppAvatar(
                  name: space.cooperativeName,
                  seed: space.cooperativeId,
                  group: true,
                  size: 44,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        space.cooperativeName,
                        maxLines: 2,
                        style: AppText.subtitle,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (space.memberCount > 0)
                            countLabel(space.memberCount, 'member', 'members'),
                          if (space.canHost) 'You can host',
                        ].join(' · '),
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (live != null) ...[
              const SizedBox(height: 12),
              _Banner(
                colour: AppStage.live,
                background: AppColors.dangerSoft,
                icon: Icons.sensors,
                label: live.title.isEmpty ? 'Meeting in progress' : live.title,
                detail: 'Live now',
              ),
            ] else if (next?.scheduledFor != null) ...[
              const SizedBox(height: 12),
              _Banner(
                colour: AppColors.primaryDark,
                background: AppColors.primarySoft,
                icon: Icons.event_outlined,
                label: next!.title.isEmpty ? 'Scheduled meeting' : next.title,
                detail: '${dayLabel(next.scheduledFor!)} at '
                    '${bubbleTime(next.scheduledFor!)}',
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: space.conversation == null
                        ? null
                        : () => _openGroup(context, space),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.line),
                      minimumSize: const Size.fromHeight(44),
                    ),
                    icon: const Icon(Icons.forum_outlined, size: 18),
                    label: const Text('Group chat'),
                  ),
                ),
                // A member with nothing to join gets no button at all: only the
                // cooperative's administrators start meetings, and a control that
                // always refuses is worse than no control.
                if (live != null || space.canHost) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _meet(context, live),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                      ),
                      icon: const Icon(Icons.videocam_outlined, size: 18),
                      label: Text(live != null ? 'Join' : 'Meet'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openGroup(BuildContext context, Space space) {
    final ref = space.conversation!;
    final conversations = context.read<ConversationsCubit>();
    final known = conversations.state.items
        .where((c) => c.id == ref.id)
        .firstOrNull;
    openThread(context, known ?? ref);
  }

  Future<void> _meet(BuildContext context, MeetingSummary? live) async {
    // Above the interactive ceiling the host hears it before the meeting starts, not
    // from members who cannot get in. Joining one that is already running is fine —
    // whoever is in is in.
    if (live == null && space.memberCount > kMeetingCeiling) {
      final go = await showModalBottomSheet<bool>(
        context: context,
        builder: (_) => const _CeilingWarning(),
      );
      if (go != true) return;
    }
    if (!context.mounted) return;

    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => GreenRoomScreen(space: space, meeting: live),
      ),
    );
    if (message == null || message.isEmpty || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The SFU's interactive ceiling — `connectra_plus`. Above this a cooperative needs
/// livestream mode, which is not in this version.
const int kMeetingCeiling = 200;

class _CeilingWarning extends StatelessWidget {
  const _CeilingWarning();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('This meeting will not hold everyone', style: AppText.title),
            const SizedBox(height: 8),
            Text(
              'This cooperative has more members than a single meeting can hold '
              '($kMeetingCeiling). Members beyond that will not be able to join.',
              style: AppText.meta,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('Start anyway'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.colour,
    required this.background,
    required this.icon,
    required this.label,
    required this.detail,
  });

  final Color colour;
  final Color background;
  final IconData icon;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colour),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.meta.copyWith(
                    color: colour,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(detail, style: AppText.caption.copyWith(color: colour)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
