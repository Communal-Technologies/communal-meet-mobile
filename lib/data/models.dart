DateTime? _date(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

String _str(dynamic v) => v == null ? '' : v.toString();

int _int(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

bool _bool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  return v?.toString() == 'true' || v?.toString() == '1';
}

class Caller {
  const Caller({
    required this.profileId,
    required this.userId,
    required this.name,
    required this.avatar,
    required this.guard,
    required this.adminCooperativeId,
    required this.hostingCooperatives,
  });

  final String profileId;
  final String userId;
  final String name;
  final String avatar;
  final String guard;
  final String adminCooperativeId;
  final List<String> hostingCooperatives;

  factory Caller.fromJson(Map<String, dynamic> json) {
    final profile = (json['profile'] as Map?)?.cast<String, dynamic>() ?? json;
    return Caller(
      profileId: _str(profile['profile_id']),
      userId: _str(profile['user_id']),
      name: _str(profile['name']),
      avatar: _str(profile['avatar']),
      guard: _str(profile['guard']),
      adminCooperativeId: _str(profile['admin_cooperative_id']),
      hostingCooperatives: ((json['hosting_cooperatives'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'profile': {
      'profile_id': profileId,
      'user_id': userId,
      'name': name,
      'avatar': avatar,
      'guard': guard,
      'admin_cooperative_id': adminCooperativeId,
    },
    'hosting_cooperatives': hostingCooperatives,
  };
}

class Conversation {
  Conversation({
    required this.id,
    required this.kind,
    required this.title,
    required this.postingPolicy,
    required this.canPost,
    required this.unread,
    required this.lastMessageAt,
    required this.lastMessagePreview,
    required this.lastMessageSeq,
    required this.mutedUntil,
    required this.cooperativeId,
    required this.cooperativeName,
    required this.myRole,
    required this.participantCount,
    required this.counterpartProfileId,
    required this.counterpartName,
    this.othersReadSeq = 0,
  });

  final String id;
  final String kind;
  final String title;
  String postingPolicy;
  bool canPost;
  int unread;
  DateTime? lastMessageAt;
  String lastMessagePreview;
  int lastMessageSeq;
  DateTime? mutedUntil;
  final String cooperativeId;
  final String cooperativeName;
  final String myRole;
  final int participantCount;
  final String counterpartProfileId;
  final String counterpartName;
  int othersReadSeq;

  bool get isGroup => kind == 'coop_group';
  bool get isMuted =>
      mutedUntil != null && mutedUntil!.toLocal().isAfter(DateTime.now());
  bool get isAdmin => myRole == 'admin';

  String get displayName =>
      isGroup ? title : (counterpartName.isEmpty ? title : counterpartName);

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: _str(json['id']),
    kind: _str(json['kind']),
    title: _str(json['title']),
    postingPolicy: _str(json['posting_policy']),
    canPost: _bool(json['can_post']),
    unread: _int(json['unread']),
    lastMessageAt: _date(json['last_message_at']),
    lastMessagePreview: _str(json['last_message_preview']),
    lastMessageSeq: _int(json['last_message_seq']),
    mutedUntil: _date(json['muted_until']),
    cooperativeId: _str(json['cooperative_id']),
    cooperativeName: _str(json['cooperative_name']),
    myRole: _str(json['my_role']),
    participantCount: _int(json['participant_count']),
    counterpartProfileId: _str(json['counterpart_profile_id']),
    counterpartName: _str(json['counterpart_name']),
    othersReadSeq: _int(json['others_read_seq']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'title': title,
    'posting_policy': postingPolicy,
    'can_post': canPost,
    'unread': unread,
    'last_message_at': lastMessageAt?.toIso8601String(),
    'last_message_preview': lastMessagePreview,
    'last_message_seq': lastMessageSeq,
    'muted_until': mutedUntil?.toIso8601String(),
    'cooperative_id': cooperativeId,
    'cooperative_name': cooperativeName,
    'my_role': myRole,
    'participant_count': participantCount,
    'counterpart_profile_id': counterpartProfileId,
    'counterpart_name': counterpartName,
    'others_read_seq': othersReadSeq,
  };
}

enum SendState { stored, queued, failed }

class Message {
  Message({
    required this.id,
    required this.conversationId,
    required this.seq,
    required this.senderProfileId,
    required this.senderName,
    required this.kind,
    required this.body,
    required this.replyToId,
    required this.clientMsgId,
    required this.createdAt,
    this.sendState = SendState.stored,
  });

  final String id;
  final String conversationId;
  final int seq;
  final String senderProfileId;
  final String senderName;
  final String kind;
  final String body;
  final String replyToId;
  final String clientMsgId;
  final DateTime createdAt;
  SendState sendState;

  bool get isSystem => kind == 'system' || kind == 'call_event';
  bool get isPending => sendState != SendState.stored;

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: _str(json['id']),
    conversationId: _str(json['conversation_id']),
    seq: _int(json['seq']),
    senderProfileId: _str(json['sender_profile_id']),
    senderName: _str(json['sender_name']),
    kind: _str(json['kind']).isEmpty ? 'text' : _str(json['kind']),
    body: _str(json['body']),
    replyToId: _str(json['reply_to_id']),
    clientMsgId: _str(json['client_msg_id']),
    createdAt: _date(json['created_at']) ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'conversation_id': conversationId,
    'seq': seq,
    'sender_profile_id': senderProfileId,
    'sender_name': senderName,
    'kind': kind,
    'body': body,
    'reply_to_id': replyToId,
    'client_msg_id': clientMsgId,
    'created_at': createdAt.toIso8601String(),
  };
}

class MeetingSummary {
  const MeetingSummary({
    required this.id,
    required this.code,
    required this.cooperativeId,
    required this.title,
    required this.style,
    required this.status,
    required this.hostProfileId,
    required this.hostName,
    required this.lobbyEnabled,
    required this.recordingEnabled,
    required this.recording,
    required this.participantCount,
    required this.scheduledFor,
    required this.startedAt,
    required this.endedAt,
  });

  final String id;
  final String code;
  final String cooperativeId;
  final String title;
  final String style;
  final String status;
  final String hostProfileId;
  final String hostName;
  final bool lobbyEnabled;

  /// Whether this meeting has ever been recorded. It stays true afterwards, so it
  /// answers "is there a recording of this" and never "is one running".
  final bool recordingEnabled;

  /// Whether a recording is running right now. This is the one the host's Record
  /// toggle reads; [recordingEnabled] would leave it stuck on for ever.
  final bool recording;

  final int participantCount;
  final DateTime? scheduledFor;
  final DateTime? startedAt;
  final DateTime? endedAt;

  bool get isLive => status == 'live';
  bool get hasEnded => status == 'ended';
  bool get isCall => style == 'call';
  String get displayTitle => title.isEmpty ? 'Meeting' : title;

  factory MeetingSummary.fromJson(Map<String, dynamic> json) => MeetingSummary(
    id: _str(json['id']),
    code: _str(json['code']),
    cooperativeId: _str(json['cooperative_id']),
    title: _str(json['title']),
    style: _str(json['style']).isEmpty ? 'meeting' : _str(json['style']),
    status: _str(json['status']),
    hostProfileId: _str(json['host_profile_id']),
    hostName: _str(json['host_name']),
    lobbyEnabled: _bool(json['lobby_enabled']),
    recordingEnabled: _bool(json['recording_enabled']),
    recording: _bool(json['recording']),
    participantCount: _int(json['participant_count']),
    scheduledFor: _date(json['scheduled_for']),
    startedAt: _date(json['started_at']),
    endedAt: _date(json['ended_at']),
  );
}

/// One ICE server as the platform issued it, for the identity that is about to
/// join. The app neither chooses these nor keeps them: they are minted per join
/// and the relay usage bills against the merchant app they came from.
class IceServer {
  const IceServer({
    required this.urls,
    required this.username,
    required this.credential,
  });

  final List<String> urls;
  final String username;
  final String credential;

  factory IceServer.fromJson(Map<String, dynamic> json) {
    final urls = json['urls'];
    return IceServer(
      urls: urls is List
          ? urls.map((e) => e.toString()).toList()
          : [_str(urls)].where((e) => e.isNotEmpty).toList(),
      username: _str(json['username']),
      credential: _str(json['credential']),
    );
  }

  Map<String, dynamic> toMap() => {
    'urls': urls,
    if (username.isNotEmpty) 'username': username,
    if (credential.isNotEmpty) 'credential': credential,
  };
}

/// Everything the phone needs to join, and nothing more. The room name, the
/// identity and the SFU address are all the backend's to decide — a client that
/// could name its own room could name another merchant's.
class JoinTicket {
  const JoinTicket({
    required this.meeting,
    required this.token,
    required this.livekitUrl,
    required this.room,
    required this.identity,
    required this.role,
    required this.canHost,
    required this.iceServers,
  });

  final MeetingSummary meeting;
  final String token;
  final String livekitUrl;
  final String room;
  final String identity;
  final String role;
  final bool canHost;
  final List<IceServer> iceServers;

  /// A lobby token publishes nothing until a host admits its holder.
  bool get isKnocking => role == 'lobby';

  factory JoinTicket.fromJson(Map<String, dynamic> json) => JoinTicket(
    meeting: MeetingSummary.fromJson(
      ((json['meeting'] as Map?) ?? const {}).cast<String, dynamic>(),
    ),
    token: _str(json['token']),
    livekitUrl: _str(json['livekit_url']),
    room: _str(json['room']),
    identity: _str(json['identity']),
    role: _str(json['role']),
    canHost: _bool(json['can_host']),
    iceServers: ((json['ice_servers'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => IceServer.fromJson(e.cast<String, dynamic>()))
        .toList(),
  );
}

/// One person's presence in a meeting: the host's participant sheet while it
/// runs, and the attendance record after it.
class MeetingAttendee {
  const MeetingAttendee({
    required this.profileId,
    required this.name,
    required this.avatar,
    required this.role,
    required this.present,
    required this.waiting,
    required this.joinedAt,
    required this.leftAt,
  });

  final String profileId;
  final String name;
  final String avatar;
  final String role;
  final bool present;
  final bool waiting;
  final DateTime? joinedAt;
  final DateTime? leftAt;

  factory MeetingAttendee.fromJson(Map<String, dynamic> json) =>
      MeetingAttendee(
        profileId: _str(json['profile_id']),
        name: _str(json['name']),
        avatar: _str(json['avatar']),
        role: _str(json['role']),
        present: _bool(json['present']),
        waiting: _bool(json['waiting']),
        joinedAt: _date(json['joined_at']),
        leftAt: _date(json['left_at']),
      );
}

/// What a mute did.
///
/// [enforced] is the field that decides the words on the screen. True means the
/// platform stopped forwarding those tracks and it holds whatever the muted phone
/// does; false means a cooperating client was asked and may not have complied.
/// Read it — never infer it from [tracks], which is legitimately zero for somebody
/// who had published nothing.
class MuteOutcome {
  const MuteOutcome({
    required this.enforced,
    required this.tracks,
    required this.alreadyMuted,
    required this.people,
    required this.failed,
  });

  final bool enforced;
  final int tracks;
  final int alreadyMuted;
  final int people;
  final int failed;

  factory MuteOutcome.fromJson(Map<String, dynamic> json) => MuteOutcome(
    enforced: _bool(json['enforced']),
    tracks: _int(json['tracks']),
    alreadyMuted: _int(json['already_muted']),
    people: _int(json['people']),
    failed: _int(json['failed']),
  );
}

class Space {
  const Space({
    required this.cooperativeId,
    required this.cooperativeName,
    required this.ledgerNumber,
    required this.role,
    required this.canHost,
    required this.memberCount,
    required this.conversation,
    required this.liveMeeting,
    required this.nextMeeting,
  });

  final String cooperativeId;
  final String cooperativeName;
  final String ledgerNumber;
  final String role;
  final bool canHost;
  final int memberCount;
  final Conversation? conversation;
  final MeetingSummary? liveMeeting;
  final MeetingSummary? nextMeeting;

  factory Space.fromJson(Map<String, dynamic> json) {
    final conv = json['conversation'];
    final live = json['live_meeting'];
    final next = json['next_meeting'];
    return Space(
      cooperativeId: _str(json['cooperative_id']),
      cooperativeName: _str(json['cooperative_name']),
      ledgerNumber: _str(json['ledger_number']),
      role: _str(json['role']),
      canHost: _bool(json['can_host']),
      memberCount: _int(json['member_count']),
      conversation: conv is Map
          ? Conversation.fromJson(conv.cast<String, dynamic>())
          : null,
      liveMeeting: live is Map
          ? MeetingSummary.fromJson(live.cast<String, dynamic>())
          : null,
      nextMeeting: next is Map
          ? MeetingSummary.fromJson(next.cast<String, dynamic>())
          : null,
    );
  }
}

class Person {
  const Person({
    required this.profileId,
    required this.name,
    required this.avatar,
  });

  final String profileId;
  final String name;
  final String avatar;

  factory Person.fromJson(Map<String, dynamic> json) => Person(
    profileId: _str(json['profile_id']),
    name: _str(json['name']),
    avatar: _str(json['avatar']),
  );
}
