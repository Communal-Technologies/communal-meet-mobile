import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../data/session_store.dart';
import 'config.dart';
import 'theme.dart';

/// The native incoming-call screen, shown when Meet is not running.
class CallKit {
  CallKit._();

  static const _appName = 'Communal Meet';

  static CallKitParams params({
    required String callId,
    required String callerName,
    required bool video,
    String avatar = '',
  }) => CallKitParams(
    id: callId,
    nameCaller: callerName.isEmpty ? 'Unknown caller' : callerName,
    appName: _appName,
    avatar: avatar.isEmpty ? null : avatar,
    handle: video ? 'Video call' : 'Voice call',
    type: video ? 1 : 0,
    duration: ringMilliseconds,
    missedCallNotification: const NotificationParams(
      showNotification: true,
      isShowCallback: true,
      subtitle: 'Missed call',
      callbackText: 'Call back',
    ),
    extra: {'call_id': callId, 'video': video},
    android: AndroidParams(
      isCustomNotification: true,
      isShowLogo: false,
      isShowCallID: false,
      ringtonePath: 'system_ringtone_default',
      backgroundColor: _hex(AppColors.primary),
      actionColor: _hex(AppColors.success),
      textColor: _hex(AppColors.white),
      incomingCallNotificationChannelName: 'Incoming calls',
      missedCallNotificationChannelName: 'Missed calls',
      isShowFullLockedScreen: true,
      isImportant: true,
      isBot: false,
      textAccept: 'Answer',
      textDecline: 'Decline',
    ),
    ios: const IOSParams(
      iconName: 'AppIcon',
      handleType: 'generic',
      supportsVideo: true,
      maximumCallGroups: 1,
      maximumCallsPerCallGroup: 1,
      supportsDTMF: false,
      supportsHolding: false,
      supportsGrouping: false,
      supportsUngrouping: false,
      includesCallsInRecents: true,
      configureAudioSession: true,
      audioSessionMode: 'voiceChat',
      audioSessionActive: true,
    ),
  );

  static const ringMilliseconds = 45000;

  static Future<void> show(Map<String, dynamic> data) async {
    final callId = (data['call_id'] ?? '').toString();
    if (callId.isEmpty) return;
    try {
      await FlutterCallkitIncoming.showCallkitIncoming(
        params(
          callId: callId,
          callerName: (data['caller_name'] ?? '').toString(),
          video: (data['video'] ?? '').toString() == 'true',
        ),
      );
    } catch (e) {
      debugPrint('callkit: could not ring ($e)');
    }
  }

  static Future<void> hide(String callId) async {
    try {
      await FlutterCallkitIncoming.endCall(callId);
    } catch (e) {
      debugPrint('callkit: could not clear the ringer ($e)');
    }
  }

  static Future<void> clearAll() async {
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (_) {
      return;
    }
  }

  /// Asks once for the grant that lets the ringer cover the lock screen.
  static Future<void> ensureFullScreen() async {
    try {
      if (await FlutterCallkitIncoming.canUseFullScreenIntent()) return;
      await FlutterCallkitIncoming.requestFullIntentPermission();
    } catch (_) {
      return;
    }
  }

  /// The PushKit token. Empty on Android.
  static Future<String> voipToken() async {
    try {
      return (await FlutterCallkitIncoming.getDevicePushTokenVoIP()) ?? '';
    } catch (_) {
      return '';
    }
  }

  static String callIdOf(CallKitParams params) {
    final extra = params.extra;
    final fromExtra = (extra == null
        ? ''
        : (extra['call_id'] ?? '').toString());
    return fromExtra.isEmpty ? params.id : fromExtra;
  }

  static String _hex(Color colour) =>
      '#${(colour.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

/// Declines a call from the background isolate, where the app's own wiring does
/// not exist.
Future<void> declineFromBackground(String callId) async {
  if (callId.isEmpty) return;
  try {
    final session = SessionStore();
    await session.load();
    final token = session.token ?? '';
    if (token.isEmpty) return;
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.requireBaseUrl(),
        headers: {'Authorization': 'Bearer $token'},
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    await dio.post(ApiPaths.callDecline(callId));
  } catch (e) {
    debugPrint('callkit: background decline failed ($e)');
  }
}

@pragma('vm:entry-point')
Future<void> handleCallkitBackgroundEvent(CallEvent event) async {
  switch (event) {
    case CallEventActionCallDecline(callKitParams: final params):
      await declineFromBackground(CallKit.callIdOf(params));
    case CallEventActionCallTimeout(id: final id):
      await declineFromBackground(id);
    default:
      return;
  }
}
