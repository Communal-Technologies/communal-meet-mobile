import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/conversations_cubit.dart';
import '../state/services.dart';
import '../state/thread_cubit.dart';
import '../widgets/composer.dart';
import '../widgets/message_bubble.dart';
import '../widgets/states.dart';
import 'conversation_details.dart';

class ThreadScreen extends StatelessWidget {
  const ThreadScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ThreadCubit(
        context.read<AppServices>(),
        context.read<ConversationsCubit>(),
        conversation,
      )..load(),
      child: const _ThreadView(),
    );
  }
}

class _ThreadView extends StatefulWidget {
  const _ThreadView();

  @override
  State<_ThreadView> createState() => _ThreadViewState();
}

class _ThreadViewState extends State<_ThreadView> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 320) {
      context.read<ThreadCubit>().loadOlder();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ThreadCubit>();
    final me = context.read<AppServices>().session.caller?.profileId ?? '';

    return BlocBuilder<ThreadCubit, ThreadState>(
      builder: (context, state) {
        final conversation = state.conversation;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: InkWell(
              onTap: () => _openDetails(context, cubit),
              child: Row(
                children: [
                  AppAvatar(
                    name: conversation.displayName,
                    seed: conversation.isGroup
                        ? conversation.cooperativeId
                        : conversation.counterpartProfileId,
                    group: conversation.isGroup,
                    size: 36,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          conversation.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.subtitle,
                        ),
                        Text(
                          _subtitle(state),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(
                            color: state.typing.isEmpty
                                ? AppColors.muted
                                : AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                tooltip: conversation.isMuted ? 'Unmute' : 'Mute',
                onPressed: () => cubit.mute(conversation.isMuted ? 0 : 60 * 8),
                icon: Icon(
                  conversation.isMuted
                      ? Icons.notifications_off
                      : Icons.notifications_none,
                ),
              ),
              IconButton(
                tooltip: 'Details',
                onPressed: () => _openDetails(context, cubit),
                icon: const Icon(Icons.info_outline),
              ),
            ],
          ),
          body: Column(
            children: [
              if (state.offline) const OfflineStrip(),
              Expanded(child: _body(context, state, cubit, me)),
              if (conversation.canPost)
                Composer(onSend: cubit.send, onChanged: cubit.composerChanged)
              else
                const LockedComposer(
                  message: 'Only administrators post in this group.',
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _body(
    BuildContext context,
    ThreadState state,
    ThreadCubit cubit,
    String me,
  ) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.isEmpty && state.error.isNotEmpty) {
      return FailureState(
        message: state.error,
        offline: state.offline,
        onRetry: cubit.load,
      );
    }
    if (state.isEmpty) {
      return EmptyState(
        asset: 'empty_chats.svg',
        title: 'No messages yet',
        body: state.conversation.canPost
            ? 'Be the first to say something.'
            : 'Announcements from your cooperative will appear here.',
      );
    }

    final rows = _rows(state, me);
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: rows.length + (state.loadingOlder ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= rows.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return rows[rows.length - 1 - i];
      },
    );
  }

  List<Widget> _rows(ThreadState state, String me) {
    final all = [...state.messages, ...state.pending];
    final rows = <Widget>[];
    DateTime? day;
    for (var i = 0; i < all.length; i++) {
      final message = all[i];
      if (day == null || !sameDay(day, message.createdAt)) {
        day = message.createdAt;
        rows.add(DaySeparator(message.createdAt));
      }
      if (message.isSystem) {
        rows.add(SystemNote(message));
        continue;
      }
      final previous = i == 0 ? null : all[i - 1];
      final showSender =
          state.conversation.isGroup &&
          (previous == null ||
              previous.senderProfileId != message.senderProfileId ||
              previous.isSystem);
      rows.add(
        MessageBubble(
          message: message,
          mine: message.senderProfileId == me,
          showSender: showSender,
          read: message.seq > 0 && message.seq <= state.readUpTo,
          onRetry: () => context.read<ThreadCubit>().retry(message.clientMsgId),
          onDiscard: () =>
              context.read<ThreadCubit>().discard(message.clientMsgId),
        ),
      );
    }
    return rows;
  }

  String _subtitle(ThreadState state) {
    if (state.typing.isNotEmpty) {
      if (state.typing.length == 1) {
        return '${firstName(state.typing.first)} is typing…';
      }
      return '${state.typing.length} people are typing…';
    }
    final conversation = state.conversation;
    if (conversation.isGroup) {
      if (conversation.participantCount > 0) {
        return countLabel(conversation.participantCount, 'member', 'members');
      }
      return conversation.cooperativeName;
    }
    return conversation.cooperativeName;
  }

  Future<void> _openDetails(BuildContext context, ThreadCubit cubit) {
    final conversations = context.read<ConversationsCubit>();
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: cubit),
            BlocProvider.value(value: conversations),
          ],
          child: const ConversationDetailsScreen(),
        ),
      ),
    );
  }
}
