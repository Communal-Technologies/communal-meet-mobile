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
    required this.title,
    required this.status,
    required this.hostName,
    required this.participantCount,
    required this.scheduledFor,
    required this.startedAt,
  });

  final String id;
  final String title;
  final String status;
  final String hostName;
  final int participantCount;
  final DateTime? scheduledFor;
  final DateTime? startedAt;

  factory MeetingSummary.fromJson(Map<String, dynamic> json) => MeetingSummary(
    id: _str(json['id']),
    title: _str(json['title']),
    status: _str(json['status']),
    hostName: _str(json['host_name']),
    participantCount: _int(json['participant_count']),
    scheduledFor: _date(json['scheduled_for']),
    startedAt: _date(json['started_at']),
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
