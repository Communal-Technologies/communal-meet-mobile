import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/api_client.dart';
import '../data/models.dart';
import '../state/meeting_cubit.dart' show MeetingExit;
import '../state/services.dart';
import '../widgets/participant_tile.dart';
import 'meeting.dart' show elapsedLabel;

/// What happened, after the meeting. It replaces the stage rather than sitting on top of
/// it, so back from here goes to the cooperative and never rejoins.
class MeetingSummaryScreen extends StatefulWidget {
  const MeetingSummaryScreen({
    super.key,
    required this.meeting,
    required this.coopName,
    required this.message,
    required this.duration,
    required this.wasHost,
    this.hasChat = false,
  });

  final MeetingSummary meeting;
  final String coopName;

  /// Why this ended, when it was not the member's own choice — "The host ended the
  /// meeting", "You were removed from the meeting". Empty for an ordinary leave.
  final String message;

  final Duration? duration;
  final bool wasHost;
  final bool hasChat;

  @override
  State<MeetingSummaryScreen> createState() => _MeetingSummaryScreenState();
}

class _MeetingSummaryScreenState extends State<MeetingSummaryScreen> {
  List<MeetingAttendee> _people = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The roster is the one thing here that is not already known, and it is not worth an
  /// error state — a summary that cannot list who came is still a summary.
  Future<void> _load() async {
    try {
      final list = await context.read<AppServices>().meetings.participants(
        widget.meeting.id,
      );
      if (!mounted) return;
      setState(() {
        _people = list;
        _loading = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.duration;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.message.isEmpty ? 'You left the meeting' : widget.message,
                style: AppText.display,
              ),
              const SizedBox(height: 6),
              Text(
                widget.coopName.isEmpty
                    ? widget.meeting.displayTitle
                    : '${widget.meeting.displayTitle} · ${widget.coopName}',
                style: AppText.meta,
              ),
              const SizedBox(height: 20),
              if (duration != null)
                _Fact(
                  icon: Icons.schedule,
                  label: 'You were in for ${_spoken(duration)}',
                ),
              _Fact(
                icon: Icons.people_outline,
                label: _attendance(),
              ),
              if (widget.wasHost && widget.meeting.recordingEnabled)
                _Fact(
                  icon: Icons.fiber_manual_record_outlined,
                  label: 'The recording will be saved when everyone has left.',
                ),
              const SizedBox(height: 16),
              Expanded(child: _roster()),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(const MeetingExit()),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text('Done'),
              ),
              if (widget.hasChat) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(
                    const MeetingExit(openChat: true),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: const Text('Open chat'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _attendance() {
    if (_loading) return 'Counting who was here…';
    if (_people.isEmpty) {
      return countLabel(
        widget.meeting.participantCount,
        'person was here',
        'people were here',
      );
    }
    return countLabel(_people.length, 'person was here', 'people were here');
  }

  Widget _roster() {
    if (_loading || _people.isEmpty) return const SizedBox.shrink();
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _people.length,
      itemBuilder: (context, i) {
        final who = _people[i];
        final host = who.profileId == widget.meeting.hostProfileId;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: StageAvatar(name: who.name, seed: who.profileId, size: 36),
          title: Text(
            who.name.isEmpty ? 'Someone' : who.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body,
          ),
          subtitle: host ? Text('Host', style: AppText.caption) : null,
        );
      },
    );
  }
}

/// `4 minutes`, and `1:04:12` once it is long enough that minutes stop being useful.
String _spoken(Duration d) {
  if (d.inMinutes < 1) return 'less than a minute';
  if (d.inHours < 1) return countLabel(d.inMinutes, 'minute', 'minutes');
  return elapsedLabel(d);
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: AppText.body)),
        ],
      ),
    );
  }
}
