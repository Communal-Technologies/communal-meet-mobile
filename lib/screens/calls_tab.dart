import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/calls_cubit.dart';
import '../state/session_cubit.dart';
import '../widgets/states.dart';
import 'call_launcher.dart';

class CallsTab extends StatelessWidget {
  const CallsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CallsCubit>();
    final me = context.select<SessionCubit, String>(
      (s) => s.state.caller?.profileId ?? '',
    );
    return BlocBuilder<CallsCubit, CallsState>(
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
            asset: 'empty_calls.svg',
            title: 'No calls yet',
            body:
                'Call anyone in your cooperative from their chat, and the '
                'call appears here afterwards.',
          );
        }
        return RefreshIndicator(
          onRefresh: cubit.refresh,
          color: AppColors.primary,
          child: ListView.separated(
            itemCount: state.items.length,
            separatorBuilder: (_, _) => const Divider(indent: 74),
            itemBuilder: (context, i) =>
                _CallRow(call: state.items[i], selfProfileId: me),
          ),
        );
      },
    );
  }
}

class _CallRow extends StatelessWidget {
  const _CallRow({required this.call, required this.selfProfileId});

  final CallRecord call;
  final String selfProfileId;

  @override
  Widget build(BuildContext context) {
    final outgoing = call.placedBy(selfProfileId);
    final missed = !call.wasAnswered && !outgoing;
    final name = call.otherName(selfProfileId);
    return ListTile(
      leading: AppAvatar(name: name, seed: call.otherProfileId(selfProfileId)),
      title: Text(
        name.isEmpty ? 'Unknown' : name,
        style: AppText.subtitle.copyWith(
          color: missed ? AppColors.danger : AppColors.ink,
        ),
      ),
      subtitle: Row(
        children: [
          Icon(
            outgoing ? Icons.call_made : Icons.call_received,
            size: 14,
            color: missed ? AppColors.danger : AppColors.muted,
          ),
          const SizedBox(width: 6),
          Text(_label(outgoing, missed), style: AppText.meta),
          const Spacer(),
          Text(listTime(call.startedAt), style: AppText.meta),
        ],
      ),
      trailing: IconButton(
        tooltip: call.video ? 'Video call' : 'Voice call',
        icon: Icon(
          call.video ? Icons.videocam_outlined : Icons.call_outlined,
          color: AppColors.primary,
        ),
        onPressed: () => placeCall(
          context,
          profileId: call.otherProfileId(selfProfileId),
          name: name,
          video: call.video,
        ),
      ),
    );
  }

  String _label(bool outgoing, bool missed) {
    if (missed) return call.status == 'declined' ? 'Declined' : 'Missed';
    if (!call.wasAnswered) return outgoing ? 'No answer' : 'Missed';
    final answered = call.answeredAt;
    final ended = call.endedAt;
    if (answered != null && ended != null) {
      return callDuration(ended.difference(answered).inSeconds);
    }
    return outgoing ? 'Outgoing' : 'Incoming';
  }
}
