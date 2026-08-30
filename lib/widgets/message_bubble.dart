import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';

class DaySeparator extends StatelessWidget {
  const DaySeparator(this.at, {super.key});

  final DateTime at;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.line),
          ),
          child: Text(dayLabel(at), style: AppText.caption),
        ),
      ),
    );
  }
}

class SystemNote extends StatelessWidget {
  const SystemNote(this.message, {super.key});

  final Message message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 6),
      child: Center(
        child: Text(
          message.body,
          textAlign: TextAlign.center,
          style: AppText.caption,
        ),
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.showSender,
    required this.read,
    this.onRetry,
    this.onDiscard,
  });

  final Message message;
  final bool mine;
  final bool showSender;
  final bool read;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: width * 0.78),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: mine ? AppColors.primary : AppColors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: Radius.circular(mine ? 14 : 4),
          bottomRight: Radius.circular(mine ? 4 : 14),
        ),
        border: mine ? null : Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showSender && !mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                message.senderName,
                style: AppText.caption.copyWith(
                  color: hueFor(message.senderProfileId),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Text(
            message.body,
            style: AppText.body.copyWith(
              color: mine ? AppColors.white : AppColors.ink,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                bubbleTime(message.createdAt),
                style: AppText.caption.copyWith(
                  fontSize: 10,
                  color: mine
                      ? AppColors.white.withValues(alpha: 0.75)
                      : AppColors.muted,
                ),
              ),
              if (mine) ...[
                const SizedBox(width: 5),
                _status(),
              ],
            ],
          ),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(
        left: mine ? 48 : 12,
        right: mine ? 12 : 48,
        top: 2,
        bottom: 2,
      ),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          bubble,
          if (message.sendState == SendState.failed)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Not sent',
                    style: AppText.caption.copyWith(color: AppColors.danger),
                  ),
                  TextButton(
                    onPressed: onRetry,
                    style: _tiny,
                    child: const Text('Retry'),
                  ),
                  TextButton(
                    onPressed: onDiscard,
                    style: _tiny.copyWith(
                      foregroundColor: const WidgetStatePropertyAll(
                        AppColors.muted,
                      ),
                    ),
                    child: const Text('Discard'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _status() {
    switch (message.sendState) {
      case SendState.queued:
        return Icon(
          Icons.schedule,
          size: 12,
          color: AppColors.white.withValues(alpha: 0.75),
        );
      case SendState.failed:
        return const Icon(Icons.error_outline, size: 12, color: Colors.white);
      case SendState.stored:
        return Icon(
          read ? Icons.done_all : Icons.done,
          size: 13,
          color: AppColors.white.withValues(alpha: read ? 1 : 0.75),
        );
    }
  }

  static final ButtonStyle _tiny = TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    minimumSize: const Size(0, 30),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
  );
}
