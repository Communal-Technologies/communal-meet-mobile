import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../state/meeting_cubit.dart';

/// The in-call chat: a sheet over the stage, and not the cooperative's chat.
///
/// It rides the LiveKit data channel with the same payload the browser client uses, so a
/// member on a phone and an officer on a laptop are in one conversation. It is ephemeral,
/// and the sheet says so once at the top rather than leaving somebody to discover it when
/// the meeting ends — what survives is a single line in the group chat.
class StageChatSheet extends StatefulWidget {
  const StageChatSheet({super.key});

  @override
  State<StageChatSheet> createState() => _StageChatSheetState();
}

class _StageChatSheetState extends State<StageChatSheet> {
  final _controller = TextEditingController();
  bool _canSend = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    setState(() => _canSend = false);
    context.read<MeetingCubit>().sendChat(text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.72,
        decoration: const BoxDecoration(
          color: AppStage.tile,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Messages',
                      style: AppText.subtitle.copyWith(
                        color: AppStage.onStage,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close,
                      color: AppStage.onStageMuted,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Messages here are only for this meeting.',
                style: AppText.caption.copyWith(color: AppStage.onStageMuted),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: BlocBuilder<MeetingCubit, MeetingState>(
                buildWhen: (a, b) => a.chat != b.chat,
                builder: (context, state) {
                  if (state.chat.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          'Nothing here yet. A message you send goes to everyone '
                          'in the meeting.',
                          textAlign: TextAlign.center,
                          style: AppText.meta.copyWith(
                            color: AppStage.onStageMuted,
                          ),
                        ),
                      ),
                    );
                  }
                  final lines = state.chat;
                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: lines.length,
                    itemBuilder: (context, i) =>
                        _Line(line: lines[lines.length - 1 - i]),
                  );
                },
              ),
            ),
            _Composer(
              controller: _controller,
              canSend: _canSend,
              onChanged: (value) {
                final can = value.trim().isNotEmpty;
                if (can != _canSend) setState(() => _canSend = can);
              },
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.line});

  final StageLine line;

  @override
  Widget build(BuildContext context) {
    if (line.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Text(
          line.body,
          textAlign: TextAlign.center,
          style: AppText.caption.copyWith(color: AppStage.onStageMuted),
        ),
      );
    }
    return Align(
      alignment: line.isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: line.isOwn ? AppColors.primary : AppStage.stage,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(line.isOwn ? 14 : 4),
            bottomRight: Radius.circular(line.isOwn ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!line.isOwn)
              Text(
                line.sender,
                style: AppText.caption.copyWith(
                  color: hueForStage(line.sender),
                  fontWeight: FontWeight.w700,
                ),
              ),
            Text(
              line.body,
              style: AppText.body.copyWith(color: AppStage.onStage),
            ),
            Text(
              bubbleTime(line.at),
              style: AppText.caption.copyWith(
                color: AppStage.onStageMuted,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The sender hues are chosen against white, and on a near-black bubble the darkest of
/// them disappear — so they are lightened for the stage rather than a second palette
/// being invented for it.
Color hueForStage(String seed) {
  final base = HSLColor.fromColor(hueFor(seed));
  return base.withLightness((base.lightness + 0.3).clamp(0.0, 0.78)).toColor();
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.canSend,
    required this.onChanged,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool canSend;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppStage.tileLine)),
      ),
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: 8 + MediaQuery.viewPaddingOf(context).bottom * 0.4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style: AppText.body.copyWith(color: AppStage.onStage),
              cursorColor: AppColors.primary,
              decoration: InputDecoration(
                hintText: 'Message the meeting',
                hintStyle: AppText.body.copyWith(
                  color: AppStage.onStageMuted,
                ),
                fillColor: AppStage.stage,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(color: AppStage.tileLine),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(color: AppStage.tileLine),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 1.4,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Semantics(
            button: true,
            label: 'Send',
            child: IconButton.filled(
              onPressed: canSend ? onSend : null,
              iconSize: 20,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppStage.tileLine,
                foregroundColor: AppColors.white,
                disabledForegroundColor: AppStage.onStageMuted,
                minimumSize: const Size(46, 46),
              ),
              icon: const Icon(Icons.send_rounded),
            ),
          ),
        ],
      ),
    );
  }
}
