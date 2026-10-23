import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../state/services.dart';
import '../state/session_cubit.dart';
import 'call.dart';

/// Places a call and opens its screen, asking for the devices it needs first.
Future<void> placeCall(
  BuildContext context, {
  required String profileId,
  required String name,
  required bool video,
}) async {
  final granted = await _permissions(video);
  if (!context.mounted) return;
  if (!granted) {
    _say(
      context,
      video
          ? 'Meet needs the camera and microphone to place a video call.'
          : 'Meet needs the microphone to place a call.',
    );
    return;
  }

  final services = context.read<AppServices>();
  final me = context.read<SessionCubit>().state.caller?.profileId ?? '';
  CallTicket ticket;
  try {
    ticket = await services.calls.place(profileId, video: video);
  } on ApiException catch (e) {
    if (context.mounted) {
      _say(
        context,
        e.isNotFound
            ? 'You can only call members of a cooperative you share.'
            : e.message,
      );
    }
    return;
  }
  if (!context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          CallScreen(ticket: ticket, outgoing: true, selfProfileId: me),
    ),
  );
}

Future<bool> _permissions(bool video) async {
  final wanted = video
      ? [Permission.microphone, Permission.camera]
      : [Permission.microphone];
  try {
    final results = await wanted.request();
    return results.values.every((s) => s.isGranted || s.isLimited);
  } catch (_) {
    return false;
  }
}

void _say(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}
