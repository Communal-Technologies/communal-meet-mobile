import 'package:flutter/foundation.dart';

class AppConfig {
  static const String env = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );
  static const String baseUrl = String.fromEnvironment('BASE_URL');

  /// Set by tests only, and null in every build.
  ///
  /// [baseUrl] is a compile-time constant, so without this a test cannot construct
  /// anything that builds an `ApiClient` — which is `AppServices`, which is the whole boot
  /// path. That is why the wiring had no test to its name until two defects came out of
  /// it. The alternative was a `--dart-define` on every `flutter test` invocation, and an
  /// undocumented `--dart-define` is what caused the first of those two defects.
  @visibleForTesting
  static String? testBaseUrl;

  static const int pinLength = 6;
  static const String platform = 'mobile_app';

  static bool get isDevelopment => env == 'development';

  static String requireBaseUrl() {
    final baseUrl = testBaseUrl ?? AppConfig.baseUrl;
    if (baseUrl.isEmpty) {
      throw StateError(
        'BASE_URL is not set. Run with '
        '--dart-define=BASE_URL=http://127.0.0.1:8989',
      );
    }
    return baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
  }
}

class ApiPaths {
  static const String authV1 = '/api/v1';
  static const String meetV1 = '/api/meet/v1';

  static const String loginChecker = '$authV1/login-checker';
  static const String login = '$authV1/login';
  static const String refreshToken = '$authV1/refresh-token';
  static const String takeoverVerify = '$authV1/login/session-takeover/verify';
  static const String takeoverResend =
      '$authV1/login/session-takeover/resend-otp';
  static const String deviceToken = '$authV1/profile/device-token';

  static const String me = '$meetV1/me';
  static const String spaces = '$meetV1/spaces';
  static const String conversations = '$meetV1/conversations';
  static const String dm = '$meetV1/conversations/dm';

  static String conversation(String id) => '$meetV1/conversations/$id';
  static String messages(String id) => '$meetV1/conversations/$id/messages';
  static String read(String id) => '$meetV1/conversations/$id/read';
  static String typing(String id) => '$meetV1/conversations/$id/typing';
  static String mute(String id) => '$meetV1/conversations/$id/mute';
  static String postingPolicy(String id) =>
      '$meetV1/conversations/$id/posting-policy';
  static String participants(String id) =>
      '$meetV1/conversations/$id/participants';
  static String presence(String id) => '$meetV1/conversations/$id/presence';

  static const String meetings = '$meetV1/meetings';
  static const String meetingLookup = '$meetV1/meetings/lookup';

  static String meetingJoin(String id) => '$meetings/$id/join';
  static String meetingLeave(String id) => '$meetings/$id/leave';
  static String meetingEnd(String id) => '$meetings/$id/end';
  static String meetingParticipants(String id) => '$meetings/$id/participants';
  static String meetingLobby(String id) => '$meetings/$id/lobby';
  static String meetingAdmit(String id, String profileId) =>
      '$meetings/$id/lobby/$profileId/admit';
  static String meetingDeny(String id, String profileId) =>
      '$meetings/$id/lobby/$profileId/deny';
  // Everybody, and one person: the same route with and without a profile id, so
  // the two are the same authorisation and the same reply shape.
  static String meetingMuteAll(String id) => '$meetings/$id/participants/mute';
  static String meetingMute(String id, String profileId) =>
      '$meetings/$id/participants/$profileId/mute';
  static String meetingRemove(String id, String profileId) =>
      '$meetings/$id/participants/$profileId/remove';
  static String recordingStart(String id) => '$meetings/$id/recording/start';
  static String recordingStop(String id) => '$meetings/$id/recording/stop';

  static Uri socket(String base, String token) {
    final http = Uri.parse('$base$meetV1/ws');
    return http.replace(
      scheme: http.scheme == 'https' ? 'wss' : 'ws',
      queryParameters: {'token': token},
    );
  }
}
