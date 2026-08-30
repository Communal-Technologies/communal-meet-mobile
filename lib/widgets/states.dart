import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/format.dart';
import '../core/theme.dart';

class Illustration extends StatelessWidget {
  const Illustration(this.asset, {super.key, this.width = 104, this.tint});

  final String asset;
  final double width;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final colour = tint ?? AppColors.primary.withValues(alpha: 0.34);
    return SvgPicture.asset(
      'assets/images/$asset',
      width: width,
      colorFilter: ColorFilter.mode(colour, BlendMode.srcIn),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.asset,
    required this.title,
    required this.body,
    this.action,
  });

  final String asset;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Illustration(asset),
            const SizedBox(height: 24),
            Text(title, style: AppText.title, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(body, style: AppText.meta, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

class FailureState extends StatelessWidget {
  const FailureState({
    super.key,
    required this.message,
    required this.onRetry,
    this.offline = false,
  });

  final String message;
  final VoidCallback onRetry;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      asset: offline ? 'state_offline.svg' : 'state_error.svg',
      title: offline ? 'You are offline' : 'That did not load',
      body: message,
      action: SizedBox(
        width: 180,
        child: FilledButton(onPressed: onRetry, child: const Text('Try again')),
      ),
    );
  }
}

class OfflineStrip extends StatelessWidget {
  const OfflineStrip({super.key, this.label = 'Offline — reconnecting'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.warningSoft,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 15, color: AppColors.warning),
          const SizedBox(width: 8),
          Text(label, style: AppText.caption.copyWith(color: AppColors.warning)),
        ],
      ),
    );
  }
}

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.name,
    this.seed,
    this.size = 46,
    this.group = false,
  });

  final String name;
  final String? seed;
  final double size;
  final bool group;

  @override
  Widget build(BuildContext context) {
    final colour = group ? AppColors.primary : hueFor(seed ?? name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colour.withValues(alpha: group ? 0.12 : 0.14),
        shape: BoxShape.circle,
      ),
      child: group
          ? Icon(Icons.groups_rounded, size: size * 0.52, color: colour)
          : Text(
              initials(name),
              style: AppText.subtitle.copyWith(
                color: colour,
                fontSize: size * 0.34,
              ),
            ),
    );
  }
}

class UnreadPip extends StatelessWidget {
  const UnreadPip(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: AppText.caption.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
