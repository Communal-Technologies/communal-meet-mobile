import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/conversations_cubit.dart';
import '../state/spaces_cubit.dart';
import '../widgets/states.dart';
import 'chats_tab.dart';

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
            offline: state.offline,
            onRetry: cubit.load,
          );
        }
        if (state.items.isEmpty) {
          return const EmptyState(
            asset: 'empty_coops.svg',
            title: 'You are not in a cooperative yet',
            body: 'Join one in the Communal app and its group chat and '
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
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _notYet(context),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                    icon: const Icon(Icons.videocam_outlined, size: 18),
                    label: Text(live != null ? 'Join' : 'Meet'),
                  ),
                ),
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

  void _notYet(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Meetings arrive in the next build of this app.'),
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
