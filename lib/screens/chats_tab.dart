import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/theme.dart';
import '../data/api_client.dart';
import '../data/models.dart';
import '../data/socket.dart';
import '../state/conversations_cubit.dart';
import '../state/services.dart';
import '../widgets/conversation_row.dart';
import '../widgets/states.dart';
import 'thread.dart';

class ChatsTab extends StatelessWidget {
  const ChatsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ConversationsCubit>();
    return Column(
      children: [
        const _SocketStrip(),
        Expanded(
          child: BlocBuilder<ConversationsCubit, ConversationsState>(
            builder: (context, state) {
              if (state.loading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state.isEmpty && state.error.isNotEmpty) {
                return FailureState(
                  message: state.error,
                  trouble: state.trouble,
                  onRetry: cubit.refresh,
                );
              }
              if (state.isEmpty) {
                return const EmptyState(
                  asset: 'empty_chats.svg',
                  title: 'No chats yet',
                  body: 'Your cooperative’s group chat appears here as soon '
                      'as you are a member of one.',
                );
              }
              return RefreshIndicator(
                onRefresh: cubit.refresh,
                color: AppColors.primary,
                child: ListView.separated(
                  itemCount: state.items.length,
                  separatorBuilder: (_, _) => const Divider(indent: 74),
                  itemBuilder: (context, i) {
                    final conversation = state.items[i];
                    return ConversationRow(
                      conversation: conversation,
                      onTap: () => openThread(context, conversation),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

Future<void> openThread(
  BuildContext context,
  Conversation conversation,
) async {
  final conversations = context.read<ConversationsCubit>();
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => BlocProvider.value(
        value: conversations,
        child: ThreadScreen(conversation: conversation),
      ),
    ),
  );
}

class _SocketStrip extends StatelessWidget {
  const _SocketStrip();

  @override
  Widget build(BuildContext context) {
    final services = context.read<AppServices>();
    return StreamBuilder<SocketStatus>(
      stream: services.socket.status,
      initialData: services.socket.currentStatus,
      builder: (context, snapshot) {
        if (snapshot.data != SocketStatus.waiting) {
          return const SizedBox.shrink();
        }
        // A socket that is down says only that it is down. Whether that is the phone or
        // us is a question the phone can answer, and it is the difference between
        // "check your data" and "we are working on it".
        return StreamBuilder<bool>(
          stream: services.reach.changes,
          initialData: services.reach.hasTransport,
          builder: (context, transport) => OfflineStrip(
            trouble: (transport.data ?? true)
                ? Trouble.unreachable
                : Trouble.offline,
          ),
        );
      },
    );
  }
}
