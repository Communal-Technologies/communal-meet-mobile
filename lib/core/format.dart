import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'theme.dart';

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

Color hueFor(String seed) {
  if (seed.isEmpty) return kSenderHues.first;
  var h = 0;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return kSenderHues[h % kSenderHues.length];
}

String firstName(String name) {
  final t = name.trim();
  if (t.isEmpty) return t;
  return t.split(RegExp(r'\s+')).first;
}

String listTime(DateTime? at) {
  if (at == null) return '';
  final local = at.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(local.year, local.month, local.day);
  final days = today.difference(that).inDays;
  if (days == 0) return DateFormat('HH:mm').format(local);
  if (days == 1) return 'Yesterday';
  if (days < 7) return DateFormat('EEE').format(local);
  return DateFormat('dd/MM/yy').format(local);
}

String bubbleTime(DateTime at) => DateFormat('HH:mm').format(at.toLocal());

String dayLabel(DateTime at) {
  final local = at.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(local.year, local.month, local.day);
  final days = today.difference(that).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 365) return DateFormat('EEE d MMM').format(local);
  return DateFormat('d MMM yyyy').format(local);
}

bool sameDay(DateTime a, DateTime b) {
  final x = a.toLocal();
  final y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

String countLabel(int n, String one, String many) =>
    '$n ${n == 1 ? one : many}';
