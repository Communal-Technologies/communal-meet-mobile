import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import 'states.dart';

class ConversationRow extends StatelessWidget {
  const ConversationRow({
    super.key,
    required this.conversation,
    required this.onTap,
  });

  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = conversation.unread;
    final preview = conversation.lastMessagePreview.isEmpty
        ? (conversation.isGroup
              ? 'No messages yet — say hello'
              : 'No messages yet')
        : conversation.lastMessagePreview;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppAvatar(
              name: conversation.displayName,
              seed: conversation.isGroup
                  ? conversation.cooperativeId
                  : conversation.counterpartProfileId,
              group: conversation.isGroup,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.subtitle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        listTime(conversation.lastMessageAt),
                        style: AppText.caption.copyWith(
                          color: unread > 0
                              ? AppColors.primary
                              : AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.meta.copyWith(
                            color: unread > 0
                                ? AppColors.ink
                                : AppColors.muted,
                            fontWeight: unread > 0
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (conversation.isMuted) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.notifications_off_outlined,
                          size: 15,
                          color: AppColors.muted,
                        ),
                      ],
                      if (unread > 0) ...[
                        const SizedBox(width: 8),
                        UnreadPip(unread),
                      ],
                    ],
                  ),
                  if (conversation.isGroup &&
                      conversation.cooperativeName.isNotEmpty &&
                      conversation.cooperativeName !=
                          conversation.displayName) ...[
                    const SizedBox(height: 4),
                    Text(
                      conversation.cooperativeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
