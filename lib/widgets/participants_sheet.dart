import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/theme.dart';
import '../data/api_client.dart';
import '../data/models.dart';
import '../state/meeting_cubit.dart';
import '../state/services.dart';
import 'participant_tile.dart';

/// Who is in the meeting, and — for a host — what can be done about them.
///
/// The roster comes from meetsvc, which knows everybody who was admitted; the live mic
/// state comes from the room, which knows who is audible right now. They are keyed
/// differently, and [MeetingCubit.tileFor] is the mapping between them.
class ParticipantsSheet extends StatefulWidget {
  const ParticipantsSheet({super.key});

  @override
  State<ParticipantsSheet> createState() => _ParticipantsSheetState();
}

class _ParticipantsSheetState extends State<ParticipantsSheet> {
  List<MeetingAttendee> _people = const [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cubit = context.read<MeetingCubit>();
    final services = context.read<AppServices>();
    try {
      final list = await services.meetings.participants(cubit.meetingId);
      if (!mounted) return;
      setState(() {
        _people = list.where((p) => p.present).toList();
        _loading = false;
        _error = '';
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  void _say(String message) {
    if (message.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _mute(MeetingAttendee who) async {
    final cubit = context.read<MeetingCubit>();
    _say(await cubit.mute(profileId: who.profileId, who: who.name));
  }

  Future<void> _remove(MeetingAttendee who) async {
    final cubit = context.read<MeetingCubit>();
    final sure = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppStage.tile,
      builder: (context) => StageConfirm(
        title: 'Remove ${who.name.isEmpty ? 'this person' : who.name}?',
        body: 'They leave the meeting straight away. They can be let back in '
            'if you change your mind.',
        action: 'Remove',
      ),
    );
    if (sure != true) return;
    _say(await cubit.remove(who.profileId, who: who.name));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<MeetingCubit>();
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.7,
      decoration: const BoxDecoration(
        color: AppStage.tile,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _loading
                        ? 'In the meeting'
                        : 'In the meeting · ${_people.length}',
                    style: AppText.subtitle.copyWith(color: AppStage.onStage),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _load,
                  icon: const Icon(
                    Icons.refresh,
                    color: AppStage.onStageMuted,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: AppStage.onStageMuted),
                ),
              ],
            ),
          ),
          Expanded(child: _body(cubit)),
        ],
      ),
    );
  }

  Widget _body(MeetingCubit cubit) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_people.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            _error.isEmpty ? 'There is no one in the meeting now.' : _error,
            textAlign: TextAlign.center,
            style: AppText.meta.copyWith(color: AppStage.onStageMuted),
          ),
        ),
      );
    }
    return BlocBuilder<MeetingCubit, MeetingState>(
      builder: (context, state) {
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 20),
          itemCount: _people.length,
          itemBuilder: (context, i) {
            final who = _people[i];
            final tile = cubit.tileFor(who.profileId);
            final isMe = tile?.isLocal ?? false;
            // Null means they are not in the room this instant — mid-reconnect, or
            // the roster is a beat ahead. It shows no live state rather than
            // claiming they are muted.
            final muted = tile != null && !tile.micOn;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: StageAvatar(
                name: who.name,
                seed: who.profileId,
                size: 40,
              ),
              title: Text(
                isMe ? '${who.name} (you)' : who.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body.copyWith(color: AppStage.onStage),
              ),
              subtitle: Row(
                children: [
                  if (muted) ...[
                    const Icon(
                      Icons.mic_off,
                      size: 13,
                      color: AppStage.onStageMuted,
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    [
                      if (who.role == 'publisher' &&
                          who.profileId == state.meeting.hostProfileId)
                        'Host',
                      if (muted) 'Muted',
                      if (tile == null) 'Not connected',
                    ].join(' · '),
                    style: AppText.caption.copyWith(
                      color: AppStage.onStageMuted,
                    ),
                  ),
                ],
              ),
              trailing: state.canHost && !isMe
                  ? PopupMenuButton<String>(
                      color: AppStage.stage,
                      icon: const Icon(
                        Icons.more_vert,
                        color: AppStage.onStageMuted,
                      ),
                      onSelected: (value) {
                        if (value == 'mute') _mute(who);
                        if (value == 'remove') _remove(who);
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'mute',
                          child: Text(
                            'Mute',
                            style: AppText.body.copyWith(
                              color: AppStage.onStage,
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'remove',
                          child: Text(
                            'Remove from meeting',
                            style: AppText.body.copyWith(color: AppStage.live),
                          ),
                        ),
                      ],
                    )
                  : null,
            );
          },
        );
      },
    );
  }
}

/// A dark confirmation, for the two things on the stage that cannot be undone.
class StageConfirm extends StatelessWidget {
  const StageConfirm({
    super.key,
    required this.title,
    required this.body,
    required this.action,
  });

  final String title;
  final String body;
  final String action;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: AppText.title.copyWith(color: AppStage.onStage),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: AppText.meta.copyWith(color: AppStage.onStageMuted),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
              ),
              child: Text(action),
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

/// The leave sheet. A host gets two actions, because a president who taps leave should
/// not accidentally end the AGM.
class LeaveSheet extends StatelessWidget {
  const LeaveSheet({super.key, required this.canHost});

  final bool canHost;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Leave the meeting?',
              style: AppText.title.copyWith(color: AppStage.onStage),
            ),
            if (canHost) ...[
              const SizedBox(height: 8),
              Text(
                'The meeting keeps going without you unless you end it for '
                'everyone.',
                style: AppText.meta.copyWith(color: AppStage.onStageMuted),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('leave'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
              ),
              child: const Text('Leave meeting'),
            ),
            if (canHost) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop('end'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppStage.onStage,
                  side: const BorderSide(color: AppStage.tileLine),
                  minimumSize: const Size.fromHeight(50),
                ),
                child: const Text('End for everyone'),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Stay'),
            ),
          ],
        ),
      ),
    );
  }
}
