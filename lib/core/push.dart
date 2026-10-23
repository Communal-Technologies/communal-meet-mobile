import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/repositories.dart';
import 'callkit.dart';

/// What a tapped notification was about.
class PushTap {
  const PushTap({
    this.conversationId = '',
    this.meetingId = '',
    this.callId = '',
  });

  final String conversationId;
  final String meetingId;
  final String callId;

  bool get isEmpty =>
      conversationId.isEmpty && meetingId.isEmpty && callId.isEmpty;

  static PushTap from(Map<String, dynamic> data) => PushTap(
    conversationId: (data['conversation_id'] ?? '').toString(),
    meetingId: (data['meeting_id'] ?? '').toString(),
    callId: (data['call_id'] ?? '').toString(),
  );
}

const _handset = MethodChannel('communal.meet/handset');

/// Reads the handset id every Communal app on this phone sees: ANDROID_ID on
/// Android, identifierForVendor on iOS. Empty is a normal answer.
Future<String> handsetId() async {
  try {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return (await _handset.invokeMethod<String>('androidId')) ?? '';
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return (await DeviceInfoPlugin().iosInfo).identifierForVendor ?? '';
    }
  } catch (_) {
    return '';
  }
  return '';
}

/// Firebase messaging, and the call that puts this install in the push address
/// book. Configured from the bundled google-services.json / GoogleService-Info.plist.
class PushService {
  PushService(this.auth, this.calls);

  final AuthRepository auth;
  final CallsRepository calls;

  final _taps = StreamController<PushTap>.broadcast();
  final _answers = StreamController<String>.broadcast();

  Stream<PushTap> get taps => _taps.stream;

  /// Calls answered on the native ringer, which the app must now join.
  Stream<String> get answers => _answers.stream;

  PushTap? pending;
  String? pendingAnswer;

  bool _started = false;
  StreamSubscription<String>? _refresh;
  StreamSubscription<RemoteMessage>? _opened;
  StreamSubscription<CallEvent?>? _callEvents;

  /// Brings Firebase up and starts listening. Safe to call more than once.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      await Firebase.initializeApp();

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      FirebaseMessaging.onBackgroundMessage(handleBackgroundMessage);

      final initial = await messaging.getInitialMessage();
      if (initial != null) pending = PushTap.from(initial.data);

      _opened = FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final tap = PushTap.from(message.data);
        if (!tap.isEmpty) _taps.add(tap);
      });

      await _startRinger();
    } catch (e) {
      debugPrint('push: not started ($e)');
      _started = false;
    }
  }

  /// Registers this install for push, and re-registers as the token rotates.
  Future<void> enrol() async {
    if (!_started) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      await _submit(token);
      _refresh ??= FirebaseMessaging.instance.onTokenRefresh.listen(_submit);
    } catch (e) {
      debugPrint('push: not enrolled ($e)');
    }
  }

  Future<void> _startRinger() async {
    await FlutterCallkitIncoming.onBackgroundMessage(
      handleCallkitBackgroundEvent,
    );
    await CallKit.ensureFullScreen();
    _callEvents = FlutterCallkitIncoming.onEvent.listen(_onCallEvent);

    try {
      for (final call in await FlutterCallkitIncoming.activeCalls()) {
        if (call.isAccepted) pendingAnswer = CallKit.callIdOf(call);
      }
    } catch (_) {
      return;
    }
  }

  void _onCallEvent(CallEvent? event) {
    switch (event) {
      case CallEventActionCallAccept(callKitParams: final params):
        final id = CallKit.callIdOf(params);
        if (id.isNotEmpty) _answers.add(id);
      case CallEventActionCallDecline(callKitParams: final params):
        _hangUp(CallKit.callIdOf(params));
      case CallEventActionCallTimeout(id: final id):
        _hangUp(id);
      case CallEventActionDidUpdateDevicePushTokenVoip():
        enrol();
      default:
        return;
    }
  }

  Future<void> _hangUp(String callId) async {
    if (callId.isEmpty) return;
    try {
      await calls.decline(callId);
    } catch (e) {
      debugPrint('push: could not decline $callId ($e)');
    }
  }

  Future<void> _submit(String? token) async {
    final value = (token ?? '').trim();
    if (value.isEmpty) return;
    try {
      await auth.registerDevice(
        token: value,
        deviceId: await handsetId(),
        platform: defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
        appVersion: await _version(),
        voipToken: await CallKit.voipToken(),
      );
    } catch (e) {
      debugPrint('push: registration refused ($e)');
    }
  }

  Future<String> _version() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return '';
    }
  }

  Future<void> dispose() async {
    await _refresh?.cancel();
    await _opened?.cancel();
    await _callEvents?.cancel();
    await _taps.close();
    await _answers.close();
  }
}

/// Required by Firebase for delivery while the app is not running. Must stay a
/// top-level function, and initialises Firebase again for its own isolate.
@pragma('vm:entry-point')
Future<void> handleBackgroundMessage(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    return;
  }
  if ((message.data['type'] ?? '').toString() == 'meet_call') {
    await CallKit.show(message.data);
  }
}
