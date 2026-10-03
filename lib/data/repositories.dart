import '../core/config.dart';
import 'api_client.dart';
import 'models.dart';

class LoginCheck {
  const LoginCheck({
    required this.login,
    required this.hasPassword,
    required this.nextStep,
    required this.otpDelivery,
  });

  final String login;
  final bool hasPassword;
  final String nextStep;
  final String otpDelivery;

  bool get needsOtp => nextStep == 'verify_otp';
}

class SignInResult {
  const SignInResult({
    required this.token,
    required this.refreshToken,
    required this.needsTakeoverOtp,
    required this.takeoverChallengeId,
    required this.otpChannel,
    required this.maskedDestination,
  });

  final String token;
  final String refreshToken;
  final bool needsTakeoverOtp;
  final String takeoverChallengeId;
  final String otpChannel;
  final String maskedDestination;

  bool get signedIn => token.isNotEmpty;
}

class AuthRepository {
  AuthRepository(this.api);

  final ApiClient api;

  Future<LoginCheck> check(String login) async {
    final body = await api.post(
      ApiPaths.loginChecker,
      body: {'login': login, 'user': 'member'},
      skipAuth: true,
    );
    return LoginCheck(
      login: body['login']?.toString() ?? login,
      hasPassword: body['password']?.toString() == '1',
      nextStep: body['next_step']?.toString() ?? 'enter_password',
      otpDelivery: body['otp_delivery']?.toString() ?? '',
    );
  }

  Future<SignInResult> signIn(String login, String pin) async {
    final body = await api.post(
      ApiPaths.login,
      body: {
        'login': login,
        'password': pin,
        'platform': AppConfig.platform,
      },
      skipAuth: true,
    );
    return SignInResult(
      token: body['token']?.toString() ?? '',
      refreshToken: body['refresh_token']?.toString() ?? '',
      needsTakeoverOtp: body['requires_session_takeover_otp'] == true,
      takeoverChallengeId: body['takeover_challenge_id']?.toString() ?? '',
      otpChannel: body['otp_channel']?.toString() ?? '',
      maskedDestination: body['masked_destination']?.toString() ?? '',
    );
  }

  Future<SignInResult> verifyTakeover({
    required String challengeId,
    required String otp,
  }) async {
    final body = await api.post(
      ApiPaths.takeoverVerify,
      body: {'takeover_challenge_id': challengeId, 'otp': otp},
      skipAuth: true,
    );
    return SignInResult(
      token: body['token']?.toString() ?? '',
      refreshToken: body['refresh_token']?.toString() ?? '',
      needsTakeoverOtp: false,
      takeoverChallengeId: '',
      otpChannel: '',
      maskedDestination: '',
    );
  }

  Future<String> resendTakeoverOtp(String challengeId) async {
    final body = await api.post(
      ApiPaths.takeoverResend,
      body: {'takeover_challenge_id': challengeId},
      skipAuth: true,
    );
    return body['masked_destination']?.toString() ?? '';
  }
}

class MeetRepository {
  MeetRepository(this.api);

  final ApiClient api;

  Future<Caller> me() async => Caller.fromJson(await api.get(ApiPaths.me));

  Future<List<Space>> spaces() async {
    final body = await api.get(ApiPaths.spaces);
    return ((body['spaces'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Space.fromJson(e.cast<String, dynamic>()))
        .toList();
  }
}

class MeetingsRepository {
  MeetingsRepository(this.api);

  final ApiClient api;

  Future<List<MeetingSummary>> forCooperative(
    String cooperativeId, {
    int limit = 20,
  }) async {
    final body = await api.get(
      ApiPaths.meetings,
      query: {'cooperative': cooperativeId, 'limit': limit},
    );
    return ((body['meetings'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => MeetingSummary.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// Opens a meeting now, or schedules one. [scheduledFor] is wall-clock text in
  /// the cooperative's own time — 'YYYY-MM-DD HH:MM', not an ISO instant — because
  /// that is what the backend stores and compares verbatim.
  Future<MeetingSummary> create({
    required String cooperativeId,
    String title = '',
    bool? lobbyEnabled,
    bool recordingEnabled = false,
    String scheduledFor = '',
  }) async {
    final body = await api.post(
      ApiPaths.meetings,
      body: {
        'cooperative_id': cooperativeId,
        'title': title,
        'lobby_enabled': ?lobbyEnabled,
        'recording_enabled': recordingEnabled,
        if (scheduledFor.isNotEmpty) 'scheduled_for': scheduledFor,
      },
    );
    return _meeting(body);
  }

  Future<MeetingSummary> byCode(String code) async {
    final body = await api.get(ApiPaths.meetingLookup, query: {'code': code});
    return _meeting(body);
  }

  Future<JoinTicket> join(String meetingId) async =>
      JoinTicket.fromJson(await api.post(ApiPaths.meetingJoin(meetingId)));

  Future<void> leave(String meetingId) async {
    await api.post(ApiPaths.meetingLeave(meetingId));
  }

  Future<MeetingSummary> end(String meetingId) async =>
      _meeting(await api.post(ApiPaths.meetingEnd(meetingId)));

  Future<List<MeetingAttendee>> participants(String meetingId) async {
    final body = await api.get(ApiPaths.meetingParticipants(meetingId));
    return ((body['participants'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => MeetingAttendee.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<List<MeetingAttendee>> lobby(String meetingId) async {
    final body = await api.get(ApiPaths.meetingLobby(meetingId));
    return ((body['waiting'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => MeetingAttendee.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<void> decideAdmission(
    String meetingId,
    String profileId, {
    required bool admit,
  }) async {
    await api.post(
      admit
          ? ApiPaths.meetingAdmit(meetingId, profileId)
          : ApiPaths.meetingDeny(meetingId, profileId),
    );
  }

  /// Mutes one person, or everybody when [profileId] is empty. There is no
  /// unmute: a host may stop a microphone being heard, and turning one back on
  /// belongs to its owner.
  Future<MuteOutcome> mute(String meetingId, {String profileId = ''}) async {
    final body = await api.post(
      profileId.isEmpty
          ? ApiPaths.meetingMuteAll(meetingId)
          : ApiPaths.meetingMute(meetingId, profileId),
    );
    return MuteOutcome.fromJson(body);
  }

  Future<void> remove(String meetingId, String profileId) async {
    await api.post(ApiPaths.meetingRemove(meetingId, profileId));
  }

  Future<MeetingSummary> setRecording(String meetingId, bool on) async =>
      _meeting(
        await api.post(
          on
              ? ApiPaths.recordingStart(meetingId)
              : ApiPaths.recordingStop(meetingId),
        ),
      );

  static MeetingSummary _meeting(Map<String, dynamic> body) {
    final nested = body['meeting'];
    return MeetingSummary.fromJson(
      nested is Map ? nested.cast<String, dynamic>() : body,
    );
  }
}

class ChatRepository {
  ChatRepository(this.api);

  final ApiClient api;

  Future<List<Conversation>> conversations() async {
    final body = await api.get(ApiPaths.conversations);
    return ((body['conversations'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Conversation.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<Conversation> conversation(String id) async {
    final body = await api.get(ApiPaths.conversation(id));
    final nested = body['conversation'];
    return Conversation.fromJson(
      nested is Map ? nested.cast<String, dynamic>() : body,
    );
  }

  Future<List<Message>> messages(
    String id, {
    int? before,
    int? after,
    int limit = 40,
  }) async {
    final body = await api.get(
      ApiPaths.messages(id),
      query: {
        'limit': limit,
        if (before != null && before > 0) 'before': before,
        if (after != null && after > 0) 'after': after,
      },
    );
    final list = ((body['messages'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Message.fromJson(e.cast<String, dynamic>()))
        .toList();
    list.sort((a, b) => a.seq.compareTo(b.seq));
    return list;
  }

  Future<Message> send(
    String id, {
    required String body,
    required String clientMsgId,
    String replyToId = '',
  }) async {
    final res = await api.post(
      ApiPaths.messages(id),
      body: {
        'body': body,
        'client_msg_id': clientMsgId,
        if (replyToId.isNotEmpty) 'reply_to_id': replyToId,
      },
    );
    final message = res['message'];
    return Message.fromJson(
      message is Map ? message.cast<String, dynamic>() : res,
    );
  }

  Future<int> markRead(String id, {int? seq}) async {
    final res = await api.post(
      ApiPaths.read(id),
      body: {if (seq != null && seq > 0) 'seq': seq},
    );
    final value = res['last_read_seq'];
    return value is num ? value.toInt() : (seq ?? 0);
  }

  Future<void> typing(String id, bool typing) async {
    await api.post(ApiPaths.typing(id), body: {'typing': typing});
  }

  Future<DateTime?> mute(String id, int minutes) async {
    final res = await api.post(ApiPaths.mute(id), body: {'minutes': minutes});
    final until = res['muted_until']?.toString();
    return until == null || until.isEmpty ? null : DateTime.tryParse(until);
  }

  Future<String> setPostingPolicy(String id, String policy) async {
    final res = await api.post(
      ApiPaths.postingPolicy(id),
      body: {'posting_policy': policy},
    );
    return res['posting_policy']?.toString() ?? policy;
  }

  Future<List<Person>> participants(String id) async {
    final body = await api.get(ApiPaths.participants(id));
    return ((body['participants'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Person.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<Set<String>> presence(String id) async {
    final body = await api.get(ApiPaths.presence(id));
    return ((body['online'] as List?) ?? const [])
        .map((e) => e.toString())
        .toSet();
  }

  Future<Conversation> openDm(String profileId) async {
    final res = await api.post(ApiPaths.dm, body: {'profile_id': profileId});
    final nested = res['conversation'];
    return Conversation.fromJson(
      nested is Map ? nested.cast<String, dynamic>() : res,
    );
  }
}
