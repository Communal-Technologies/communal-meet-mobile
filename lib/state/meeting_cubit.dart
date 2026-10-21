import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/sounds.dart';
import '../data/api_client.dart';
import '../data/models.dart';
import '../data/socket.dart';
import 'services.dart';

/// The in-call chat payload, and the one thing in this file that is a contract with
/// another codebase: `livekit-fe`'s `ChatRail` publishes and reads exactly
/// `{"type":"chat","sender":…,"message":…}` on the data channel, so a member on a
/// phone and an officer on a laptop are in the same conversation. Changing the field
/// names here silently splits the room in two.
const _typeChat = 'chat';

/// Ours alone, and ephemeral: a raised hand is not worth a row in a table.
const _typeHand = 'hand';

/// meetsvc's host-control frames. They travel the same data channel as the chat, and
/// `livekit-fe` ignores what it does not recognise, so their presence does not break a
/// browser participant.
const _controlMute = 'host.mute';
const _controlMuteAll = 'host.mute_all';
const _controlRemoved = 'host.removed';
const _controlRecording = 'host.recording';
const _controlEnded = 'host.meeting_ended';

enum MeetingPhase {
  /// Connecting to the SFU. The stage is drawn, with a spinner where the tiles go.
  connecting,

  /// Connected on a lobby token, which publishes nothing. A host is deciding.
  waiting,

  /// In the meeting.
  live,

  /// The connection dropped and LiveKit is putting it back. The last frame stays on
  /// screen; a black stage reads as "the call dropped".
  reconnecting,

  /// This member left, on purpose.
  left,

  /// The host ended it for everyone.
  ended,

  /// The host removed this member.
  removed,

  /// A host declined the knock.
  denied,

  /// It never started.
  failed,
}

/// A person, as one tile draws them.
///
/// A snapshot rather than the live [Participant], because a `Participant` mutates in
/// place: emitting the same object twice tells Flutter nothing changed, and the tile
/// keeps the muted glyph of a minute ago.
class MeetingTile {
  const MeetingTile({
    required this.identity,
    required this.name,
    required this.isLocal,
    required this.micOn,
    required this.cameraOn,
    required this.speaking,
    required this.handRaised,
    required this.quality,
    required this.video,
  });

  final String identity;
  final String name;
  final bool isLocal;
  final bool micOn;
  final bool cameraOn;
  final bool speaking;
  final bool handRaised;
  final ConnectionQuality quality;

  /// The camera track, when there is one to draw. Null is the avatar tile, which is
  /// most of an audio meeting.
  final VideoTrack? video;

  bool get weak =>
      quality == ConnectionQuality.poor || quality == ConnectionQuality.lost;
}

/// One line of in-call chat. It lives as long as the meeting does and no longer —
/// what survives is a single line in the cooperative's group chat at the end.
class StageLine {
  const StageLine({
    required this.sender,
    required this.body,
    required this.at,
    this.isSystem = false,
    this.isOwn = false,
  });

  final String sender;
  final String body;
  final DateTime at;
  final bool isSystem;
  final bool isOwn;
}

/// The tracks the green room acquired, handed to the meeting.
///
/// They are prepared before the join call so a slow join does not stall the preview,
/// and they are published on connection — which is also why the green room must stop
/// caring about them the moment it hands them over. Two owners stopping one track is
/// a dead publication.
class PreparedMedia {
  PreparedMedia({this.audio, this.video, this.micOn = true, this.cameraOn = true});

  factory PreparedMedia.none() =>
      PreparedMedia(micOn: false, cameraOn: false);

  LocalAudioTrack? audio;
  LocalVideoTrack? video;
  bool micOn;
  bool cameraOn;

  /// Stops what was never published. Called by whoever still owns them.
  Future<void> dispose() async {
    final tracks = [audio, video];
    audio = null;
    video = null;
    for (final track in tracks) {
      try {
        await track?.stop();
      } catch (_) {
        // A track being stopped twice is not a failure worth a line on screen.
      }
    }
  }
}

/// What the meeting hands back to the cooperative it was opened from.
///
/// Four routes deep — cooperative, green room, meeting, summary — and each one pops
/// with its child's result rather than replacing it. `pushReplacement` completes the
/// replaced route's future, which would have the green room popping the summary the
/// instant it appeared.
class MeetingExit {
  const MeetingExit({this.message = '', this.openChat = false});

  /// Why it ended, when it was not the member's own choice. Shown by whoever is left
  /// standing, because a denial has to land somewhere a person is looking.
  final String message;

  /// The summary's second action. It is answered where the cooperative's chat lives,
  /// not from a route that cannot reach it.
  final bool openChat;
}

/// Sentinel for a copyWith that has to be able to set a nullable field back to null —
/// the screen share, which ends.
const Object _keep = Object();

class MeetingState {
  const MeetingState({
    required this.phase,
    required this.meeting,
    required this.canHost,
    required this.identity,
    this.message = '',
    this.people = const [],
    this.screenShare,
    this.screenShareBy = '',
    this.micOn = false,
    this.cameraOn = false,
    this.screenSharing = false,
    this.handRaised = false,
    this.recording = false,
    this.unstable = false,
    this.chat = const [],
    this.unreadChat = 0,
    this.waiting = const [],
    this.connectedAt,
  });

  final MeetingPhase phase;
  final MeetingSummary meeting;
  final bool canHost;
  final String identity;

  /// The sentence for the phase that has one — why it failed, who ended it.
  final String message;

  final List<MeetingTile> people;
  final VideoTrack? screenShare;
  final String screenShareBy;

  final bool micOn;
  final bool cameraOn;
  final bool screenSharing;
  final bool handRaised;

  /// A recording is running right now. Taken from the room, which the SFU keeps
  /// current, so it is right for everybody and not only for the host who started it.
  final bool recording;

  final bool unstable;

  final List<StageLine> chat;
  final int unreadChat;

  /// Who is knocking. Hosts only — a member never learns that somebody was refused.
  final List<MeetingAttendee> waiting;

  final DateTime? connectedAt;

  bool get isOver =>
      phase == MeetingPhase.left ||
      phase == MeetingPhase.ended ||
      phase == MeetingPhase.removed ||
      phase == MeetingPhase.denied ||
      phase == MeetingPhase.failed;

  bool get alone => people.length <= 1;

  MeetingState copyWith({
    MeetingPhase? phase,
    MeetingSummary? meeting,
    bool? canHost,
    String? message,
    List<MeetingTile>? people,
    Object? screenShare = _keep,
    String? screenShareBy,
    bool? micOn,
    bool? cameraOn,
    bool? screenSharing,
    bool? handRaised,
    bool? recording,
    bool? unstable,
    List<StageLine>? chat,
    int? unreadChat,
    List<MeetingAttendee>? waiting,
    DateTime? connectedAt,
  }) => MeetingState(
    phase: phase ?? this.phase,
    meeting: meeting ?? this.meeting,
    canHost: canHost ?? this.canHost,
    identity: identity,
    message: message ?? this.message,
    people: people ?? this.people,
    screenShare: screenShare == _keep
        ? this.screenShare
        : screenShare as VideoTrack?,
    screenShareBy: screenShareBy ?? this.screenShareBy,
    micOn: micOn ?? this.micOn,
    cameraOn: cameraOn ?? this.cameraOn,
    screenSharing: screenSharing ?? this.screenSharing,
    handRaised: handRaised ?? this.handRaised,
    recording: recording ?? this.recording,
    unstable: unstable ?? this.unstable,
    chat: chat ?? this.chat,
    unreadChat: unreadChat ?? this.unreadChat,
    waiting: waiting ?? this.waiting,
    connectedAt: connectedAt ?? this.connectedAt,
  );
}

/// The meeting's whole life: connect, publish, admit, mute, record, leave.
///
/// Two flows are taken from `livekit-fe/src/hooks/useConferenceRoom.ts` rather than
/// re-derived, because getting either wrong is subtle and expensive:
///
/// **Admission is a permissions update on the connection that is already open.** A
/// lobby token connects, publishes nothing, and when a host admits, LiveKit pushes new
/// grants down the same signal connection. So the tracks are published in the
/// permissions handler and there is no second join — a client that rejoined on
/// admission would knock again and wait for ever.
///
/// **The prepared tracks are published exactly once per connection.** A reconnect
/// re-runs the connected handler, and publishing again leaves a ghost track that
/// everybody subscribes to and nobody is behind.
class MeetingCubit extends Cubit<MeetingState> {
  MeetingCubit(
    this.services, {
    required JoinTicket ticket,
    required PreparedMedia prepared,
  }) : _ticket = ticket,
       _prepared = prepared,
       super(
         MeetingState(
           phase: MeetingPhase.connecting,
           meeting: ticket.meeting,
           canHost: ticket.canHost,
           identity: ticket.identity,
           micOn: prepared.micOn,
           cameraOn: prepared.cameraOn,
         ),
       ) {
    _frames = services.socket.frames.listen(_onSocketFrame);
  }

  final AppServices services;
  final JoinTicket _ticket;
  PreparedMedia _prepared;

  late final StreamSubscription<SocketFrame> _frames;
  final _notices = StreamController<String>.broadcast();

  Room? _room;
  EventsListener<RoomEvent>? _listener;

  bool _published = false;
  bool _leaving = false;
  bool _chatOpen = false;
  final Set<String> _hands = {};

  /// Sentences that belong on top of the stage for a moment and nowhere else — "You
  /// were muted by Ada Nwosu", "Recording started". Not state, because a notice is an
  /// event: two identical ones in a row are two notices.
  Stream<String> get notices => _notices.stream;

  String get meetingId => state.meeting.id;

  Room? get room => _room;

  /// Whether there is a microphone or camera to turn on at all. A member who refused the
  /// permission in the green room gets a dead pill otherwise, which is worse than a
  /// disabled one. After publication the room answers this, and these only matter
  /// before it.
  bool get canToggleMic => _published || _prepared.audio != null;

  bool get canToggleCamera => _published || _prepared.video != null;

  // ── joining ────────────────────────────────────────────────────────────────

  Future<void> connect() async {
    final room = Room(
      roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
    );
    _room = room;
    final listener = room.createListener();
    _listener = listener;
    _wire(listener);

    // The ICE servers are the platform's, minted for this identity, and the
    // reason relay usage bills to the right merchant app. The client chooses
    // none of them.
    //
    // An empty list is not "no preference", it is "no servers": passing an
    // RTCConfiguration whose iceServers is empty replaces LiveKit's own defaults
    // with nothing, and a client behind any NAT then has no STUN to learn its
    // reflexive candidate from, so every join fails on ICE. meetsvc returns an
    // empty list whenever it cannot mint TURN credentials — by design, because a
    // relay failure must never deny a meeting — so this is the normal state
    // during a TURN outage, not an edge case. Leave the configuration alone and
    // let LiveKit use its defaults.
    final ice = [
      for (final server in _ticket.iceServers)
        RTCIceServer(
          urls: server.urls,
          username: server.username,
          credential: server.credential,
        ),
    ];

    try {
      await room.connect(
        _ticket.livekitUrl,
        _ticket.token,
        connectOptions: ice.isEmpty
            ? const ConnectOptions()
            : ConnectOptions(rtcConfiguration: RTCConfiguration(iceServers: ice)),
      );
      await WakelockPlus.enable();
    } catch (error, stack) {
      // Never shown — "SignalDisconnected" is not a sentence a member of a
      // cooperative can act on — but always recorded. This used to be `catch (_)`
      // with a comment claiming the reason was worth a log, and nothing logged
      // it, so a failed join on a handset said the same thing whatever the cause
      // and there was nowhere to start.
      debugPrint('Meet could not join ${_ticket.livekitUrl}: $error\n$stack');
      _fail('We could not join the meeting. Try again.');
    }
  }

  void _wire(EventsListener<RoomEvent> listener) {
    listener
      ..on<RoomConnectedEvent>((_) => _onConnected())
      ..on<RoomReconnectingEvent>((_) {
        if (state.phase == MeetingPhase.live) {
          emit(state.copyWith(phase: MeetingPhase.reconnecting));
        }
      })
      ..on<RoomReconnectedEvent>((_) {
        if (state.phase == MeetingPhase.reconnecting) {
          emit(state.copyWith(phase: MeetingPhase.live));
        }
        _refresh();
      })
      ..on<RoomDisconnectedEvent>((e) => _onDisconnected(e.reason))
      ..on<ParticipantConnectedEvent>((_) {
        // A chime for the ninth arrival is noise, and one that lands while this member
        // is mid-sentence lands in the recording too.
        final speaking = _room?.localParticipant?.isSpeaking ?? false;
        if (state.people.length <= 8 && !speaking) Sounds.join();
        _refresh();
      })
      ..on<ParticipantDisconnectedEvent>((e) {
        _hands.remove(e.participant.identity);
        _refresh();
      })
      ..on<ParticipantPermissionsUpdatedEvent>(_onPermissions)
      ..on<ActiveSpeakersChangedEvent>((_) => _refresh())
      ..on<TrackSubscribedEvent>((_) => _refresh())
      ..on<TrackUnsubscribedEvent>((_) => _refresh())
      ..on<LocalTrackPublishedEvent>((_) => _refresh())
      ..on<LocalTrackUnpublishedEvent>((_) => _refresh())
      ..on<TrackMutedEvent>((_) => _refresh())
      ..on<TrackUnmutedEvent>((_) => _refresh())
      ..on<ParticipantConnectionQualityUpdatedEvent>((_) => _refresh())
      ..on<RoomRecordingStatusChanged>((e) {
        emit(state.copyWith(recording: e.activeRecording));
      })
      ..on<DataReceivedEvent>(_onData);
  }

  Future<void> _onConnected() async {
    if (isClosed) return;
    final canPublish = _room?.localParticipant?.permissions.canPublish ?? false;

    // The role on the ticket says what was issued; the permissions say what is true
    // now. A knocker admitted before their client finished connecting arrives already
    // able to publish, and believing the ticket would leave them in the waiting room
    // of a meeting they are in.
    if (_ticket.isKnocking && !canPublish) {
      emit(
        state.copyWith(
          phase: MeetingPhase.waiting,
          connectedAt: DateTime.now(),
        ),
      );
      _refresh();
      return;
    }

    emit(
      state.copyWith(phase: MeetingPhase.live, connectedAt: DateTime.now()),
    );
    await _publishPrepared();
    _refresh();
    if (state.canHost && state.meeting.lobbyEnabled) _loadLobby();
  }

  void _onPermissions(ParticipantPermissionsUpdatedEvent e) {
    if (e.participant is! LocalParticipant) return;
    if (!e.permissions.canPublish) return;
    if (state.phase != MeetingPhase.waiting) return;

    // Admitted. Same connection, new grants — this is the moment the prepared tracks
    // go into the room.
    emit(state.copyWith(phase: MeetingPhase.live));
    _publishPrepared().then((_) => _refresh());
  }

  Future<void> _publishPrepared() async {
    if (_published) return;
    _published = true;

    final local = _room?.localParticipant;
    if (local == null) return;

    final prepared = _prepared;
    _prepared = PreparedMedia.none();

    try {
      if (prepared.audio != null) {
        await local.publishAudioTrack(prepared.audio!);
        if (!prepared.micOn) await local.setMicrophoneEnabled(false);
      } else {
        await local.setMicrophoneEnabled(prepared.micOn);
      }
    } catch (_) {
      // A meeting with no microphone is still a meeting a member can listen to.
    }
    try {
      if (prepared.video != null) {
        await local.publishVideoTrack(prepared.video!);
        if (!prepared.cameraOn) await local.setCameraEnabled(false);
      } else if (prepared.cameraOn) {
        await local.setCameraEnabled(true);
      }
    } catch (_) {
      // Likewise the camera.
    }
  }

  void _onDisconnected(DisconnectReason? reason) {
    if (isClosed) return;
    WakelockPlus.disable();
    if (state.isOver) return;

    if (_leaving) {
      emit(state.copyWith(phase: MeetingPhase.left));
      return;
    }
    // A knocker who is disconnected while waiting was refused: the deny path removes
    // them from the room. Saying "you were removed from the meeting" to somebody who
    // was never in it is both wrong and unkind.
    if (state.phase == MeetingPhase.waiting) {
      emit(
        state.copyWith(
          phase: MeetingPhase.denied,
          message: 'The host did not let you in.',
        ),
      );
      return;
    }
    switch (reason) {
      case DisconnectReason.participantRemoved:
        emit(
          state.copyWith(
            phase: MeetingPhase.removed,
            message: 'You were removed from the meeting.',
          ),
        );
      case DisconnectReason.roomDeleted:
        emit(
          state.copyWith(
            phase: MeetingPhase.ended,
            message: 'The meeting ended.',
          ),
        );
      default:
        emit(
          state.copyWith(
            phase: MeetingPhase.ended,
            message: 'You were disconnected from the meeting.',
          ),
        );
    }
  }

  void _fail(String message) {
    if (isClosed) return;
    WakelockPlus.disable();
    emit(state.copyWith(phase: MeetingPhase.failed, message: message));
  }

  // ── the roster ─────────────────────────────────────────────────────────────

  void _refresh() {
    final room = _room;
    if (room == null || isClosed) return;

    final local = room.localParticipant;
    final everyone = <Participant>[
      ?local,
      ...room.remoteParticipants.values,
    ];

    VideoTrack? shared;
    var sharedBy = '';
    for (final p in everyone) {
      final pub = p.getTrackPublicationBySource(TrackSource.screenShareVideo);
      final track = pub?.track;
      if (pub != null && !pub.muted && track is VideoTrack) {
        shared = track;
        sharedBy = _nameOf(p);
        break;
      }
    }

    emit(
      state.copyWith(
        people: [for (final p in everyone) _tile(p, isLocal: p == local)],
        screenShare: shared,
        screenShareBy: sharedBy,
        micOn: local?.isMicrophoneEnabled() ?? false,
        cameraOn: local?.isCameraEnabled() ?? false,
        screenSharing: local?.isScreenShareEnabled() ?? false,
        recording: room.isRecording,
        unstable:
            local?.connectionQuality == ConnectionQuality.poor ||
            local?.connectionQuality == ConnectionQuality.lost,
      ),
    );
  }

  MeetingTile _tile(Participant p, {required bool isLocal}) {
    final pub = p.getTrackPublicationBySource(TrackSource.camera);
    final track = pub?.track;
    return MeetingTile(
      identity: p.identity,
      name: isLocal ? 'You' : _nameOf(p),
      isLocal: isLocal,
      micOn: p.isMicrophoneEnabled(),
      cameraOn: p.isCameraEnabled(),
      speaking: p.isSpeaking,
      handRaised: _hands.contains(p.identity),
      quality: p.connectionQuality,
      video: track is VideoTrack && !(pub?.muted ?? true) ? track : null,
    );
  }

  /// The display name the token carried. Identity is a routing key — falling back to
  /// it would label a tile `69d40b7b…--f3a1`, so an unnamed participant gets the word
  /// for one instead.
  String _nameOf(Participant p) =>
      p.name.trim().isEmpty ? 'Someone' : p.name.trim();

  /// The live tile for a member of the roster, if they are in the room right now.
  ///
  /// The roster comes from meetsvc and is keyed by profile id; the room is keyed by
  /// media-plane identity. The mapping between them is `<businessId>--<profileId>`, and
  /// the prefix is read off **our own** ticket rather than assembled from a business id
  /// the client would then be holding — if our identity ends with our profile id, what
  /// precedes it is the prefix, whatever the platform decided it is. When it does not,
  /// this answers null and the sheet simply shows no live state, which is the right
  /// failure for something that only decorates.
  MeetingTile? tileFor(String profileId) {
    final id = identityFor(profileId);
    if (id.isEmpty) return null;
    for (final tile in state.people) {
      if (tile.identity == id) return tile;
    }
    return null;
  }

  String identityFor(String profileId) {
    final mine = _sanitise(services.session.caller?.profileId ?? '');
    final id = state.identity;
    if (mine.isEmpty || !id.endsWith(mine)) return '';
    return id.substring(0, id.length - mine.length) + _sanitise(profileId);
  }

  /// The platform's own rule for what may appear in an identity, ported from
  /// `meetsvc/internal/zerorate/naming.go` — lower-cased, and anything outside
  /// `[a-z0-9_-]` dropped.
  static String _sanitise(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_-]'), '');

  // ── the controls a member has over themselves ──────────────────────────────

  Future<void> toggleMic() async {
    if (!_published) return _togglePrepared(mic: true);
    final local = _room?.localParticipant;
    if (local == null) return;
    final want = !state.micOn;
    emit(state.copyWith(micOn: want));
    try {
      await local.setMicrophoneEnabled(want);
    } catch (_) {
      emit(state.copyWith(micOn: !want));
    }
    _refresh();
  }

  Future<void> toggleCamera() async {
    if (!_published) return _togglePrepared(mic: false);
    final local = _room?.localParticipant;
    if (local == null) return;
    final want = !state.cameraOn;
    emit(state.copyWith(cameraOn: want));
    try {
      await local.setCameraEnabled(want);
    } catch (_) {
      emit(state.copyWith(cameraOn: !want));
    }
    _refresh();
  }

  /// The same two buttons, in the waiting room, where nothing is published yet.
  ///
  /// They act on the prepared tracks: `setMicrophoneEnabled` on a lobby participant
  /// would try to publish and be refused, and what a knocker sets while they wait has to
  /// be what they join with. Muted rather than stopped — a stopped capturer published on
  /// admission is a dead track.
  Future<void> _togglePrepared({required bool mic}) async {
    final LocalTrack? track = mic ? _prepared.audio : _prepared.video;
    if (track == null) return;
    final want = mic ? !state.micOn : !state.cameraOn;
    emit(mic ? state.copyWith(micOn: want) : state.copyWith(cameraOn: want));
    if (mic) {
      _prepared.micOn = want;
    } else {
      _prepared.cameraOn = want;
    }
    try {
      if (want) {
        await track.unmute(stopOnMute: false);
      } else {
        await track.mute(stopOnMute: false);
      }
    } catch (_) {
      if (isClosed) return;
      emit(mic ? state.copyWith(micOn: !want) : state.copyWith(cameraOn: !want));
      if (mic) {
        _prepared.micOn = !want;
      } else {
        _prepared.cameraOn = !want;
      }
    }
  }

  /// Starts or stops sharing the screen.
  ///
  /// On Android this needs a `mediaProjection` foreground service to be running, which
  /// is the caller's to start — the screen sharing button asks for it before calling
  /// here, because the service needs a user-visible notification and this cubit has no
  /// business posting one.
  Future<String> toggleScreenShare() async {
    final local = _room?.localParticipant;
    if (local == null) return '';
    final want = !state.screenSharing;
    try {
      await local.setScreenShareEnabled(want);
      _refresh();
      return '';
    } catch (_) {
      _refresh();
      return want
          ? 'This phone would not let us share its screen.'
          : 'Sharing did not stop. Try again.';
    }
  }

  Future<void> toggleHand() async {
    final up = !state.handRaised;
    emit(state.copyWith(handRaised: up));
    if (up) {
      _hands.add(state.identity);
    } else {
      _hands.remove(state.identity);
    }
    _refresh();
    await _publish({'type': _typeHand, 'up': up});
  }

  // ── in-call chat ───────────────────────────────────────────────────────────

  void chatOpened() {
    _chatOpen = true;
    if (state.unreadChat != 0) emit(state.copyWith(unreadChat: 0));
  }

  void chatClosed() => _chatOpen = false;

  Future<void> sendChat(String text) async {
    final body = text.trim();
    if (body.isEmpty) return;
    final me = services.session.caller?.name ?? 'You';
    _addLine(StageLine(sender: me, body: body, at: DateTime.now(), isOwn: true));
    await _publish({'type': _typeChat, 'sender': me, 'message': body});
  }

  void _addLine(StageLine line) {
    if (isClosed) return;
    emit(
      state.copyWith(
        chat: [...state.chat, line],
        unreadChat: line.isOwn || _chatOpen ? state.unreadChat : state.unreadChat + 1,
      ),
    );
  }

  Future<void> _publish(Map<String, dynamic> payload) async {
    final local = _room?.localParticipant;
    if (local == null) return;
    try {
      await local.publishData(utf8.encode(jsonEncode(payload)), reliable: true);
    } catch (_) {
      // The data channel is not a delivery guarantee and the chat says as much.
    }
  }

  void _onData(DataReceivedEvent e) {
    if (isClosed) return;
    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(utf8.decode(e.data));
      if (decoded is! Map) return;
      payload = decoded.cast<String, dynamic>();
    } catch (_) {
      return;
    }

    final type = payload['type']?.toString() ?? '';
    final from = e.participant;

    // Host controls come from meetsvc through the server API, which sends with no
    // participant. A frame that arrives *with* one was published by somebody in the
    // room, and a member is not a host however they label their JSON.
    if (type.startsWith('host.')) {
      if (from != null) return;
      _onControl(type, payload);
      return;
    }

    switch (type) {
      case _typeChat:
        final body = payload['message']?.toString() ?? '';
        if (body.isEmpty) return;
        final sender = payload['sender']?.toString() ?? '';
        _addLine(
          StageLine(
            sender: sender.isEmpty
                ? (from == null ? 'Someone' : _nameOf(from))
                : sender,
            body: body,
            at: DateTime.now(),
          ),
        );
      case _typeHand:
        if (from == null) return;
        if (payload['up'] == false) {
          _hands.remove(from.identity);
        } else {
          _hands.add(from.identity);
        }
        _refresh();
    }
  }

  void _onControl(String type, Map<String, dynamic> payload) {
    if (payload['meeting_id'] != null &&
        payload['meeting_id'].toString() != meetingId) {
      return;
    }
    final by = payload['by']?.toString() ?? '';
    final target = payload['target']?.toString() ?? '';

    switch (type) {
      case _controlMute:
        if (target != state.identity) {
          _refresh();
          return;
        }
        // Self-mute whether or not the platform already did. When the mute was
        // enforced this is a no-op on a track the SFU has already stopped; when it was
        // the fallback, this *is* the mute. The frame does not say which, and it does
        // not need to — the effect is the same and asking would be a second round trip
        // in the one moment a room is waiting for silence.
        _muteMyself();
        _notices.add(
          by.isEmpty ? 'You were muted.' : 'You were muted by $by',
        );
      case _controlMuteAll:
        // Mute-all spares the host, and the broadcast carries no exception list, so
        // the only person who can tell they were spared is the one who pressed it.
        final mine = state.canHost && by == (services.session.caller?.name ?? '');
        if (!mine) {
          _muteMyself();
          _notices.add(
            by.isEmpty ? 'Everyone was muted.' : '$by muted everyone',
          );
        }
      case _controlRemoved:
        if (target != state.identity) return;
        emit(
          state.copyWith(
            phase: MeetingPhase.removed,
            message: by.isEmpty
                ? 'You were removed from the meeting.'
                : 'You were removed from the meeting by $by.',
          ),
        );
      case _controlRecording:
        final on = payload['on'] == true;
        emit(state.copyWith(recording: on));
        final line = on
            ? 'This meeting is being recorded.'
            : 'Recording stopped. What was recorded is saved.';
        _addLine(
          StageLine(
            sender: '',
            body: line,
            at: DateTime.now(),
            isSystem: true,
          ),
        );
        _notices.add(line);
      case _controlEnded:
        emit(
          state.copyWith(
            phase: MeetingPhase.ended,
            message: by.isEmpty
                ? 'The meeting ended.'
                : '$by ended the meeting.',
          ),
        );
    }
  }

  Future<void> _muteMyself() async {
    try {
      await _room?.localParticipant?.setMicrophoneEnabled(false);
    } catch (_) {}
    _refresh();
  }

  // ── the controls a host has over the meeting ───────────────────────────────

  /// Mutes one member, or everybody when [profileId] is empty, and answers with the
  /// sentence to show.
  ///
  /// The words come from `enforced` and never from what the app expected: `true` means
  /// the platform stopped forwarding that microphone and it holds whatever the muted
  /// phone does; `false` means a cooperating client was asked. `tracks` is legitimately
  /// zero for somebody who had published nothing, so it cannot stand in for either.
  ///
  /// There is no unmute. A host may stop a microphone being heard; turning one back on
  /// belongs to its owner.
  Future<String> mute({String profileId = '', String who = ''}) async {
    try {
      final outcome = await services.meetings.mute(
        meetingId,
        profileId: profileId,
      );
      if (profileId.isEmpty) {
        if (!outcome.enforced) return 'Everyone has been asked to mute.';
        if (outcome.failed > 0) {
          return '${outcome.people} of ${outcome.people + outcome.failed} '
              'are muted.';
        }
        return 'Everyone is muted.';
      }
      final name = who.isEmpty ? 'They' : who;
      if (!outcome.enforced) return '$name has been asked to mute.';
      return who.isEmpty ? 'Muted.' : '$who is muted.';
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String> remove(String profileId, {String who = ''}) async {
    try {
      await services.meetings.remove(meetingId, profileId);
      return who.isEmpty
          ? 'They were removed from the meeting.'
          : '$who was removed from the meeting.';
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// Starts or stops the recording. The toggle's state is [MeetingState.recording] —
  /// the meeting's `recording_enabled` stays true once it has ever been recorded and
  /// would leave the button stuck on for the rest of the meeting's life.
  Future<String> setRecording(bool on) async {
    try {
      final meeting = await services.meetings.setRecording(meetingId, on);
      emit(state.copyWith(meeting: meeting, recording: meeting.recording));
      return on
          ? 'Recording started. Everyone in the meeting has been told.'
          : 'Recording stopped. What was recorded is saved.';
    } on ApiException catch (e) {
      // A stop that failed leaves the recording running, and a host must not be told
      // otherwise, so the platform's own sentence is shown as it arrives.
      return e.message;
    }
  }

  Future<String> decide(MeetingAttendee who, {required bool admit}) async {
    emit(
      state.copyWith(
        waiting: state.waiting
            .where((p) => p.profileId != who.profileId)
            .toList(),
      ),
    );
    try {
      await services.meetings.decideAdmission(
        meetingId,
        who.profileId,
        admit: admit,
      );
      return admit ? '' : 'You did not let ${who.name} in.';
    } on ApiException catch (e) {
      _loadLobby();
      return e.message;
    }
  }

  Future<void> admitAll() async {
    for (final who in [...state.waiting]) {
      await decide(who, admit: true);
    }
  }

  Future<void> _loadLobby() async {
    if (!state.canHost) return;
    try {
      final waiting = await services.meetings.lobby(meetingId);
      if (isClosed) return;
      emit(state.copyWith(waiting: waiting));
    } on ApiException {
      // The next knock brings another frame, and the sheet has a refresh.
    }
  }

  // ── leaving ────────────────────────────────────────────────────────────────

  Future<void> leave() async {
    _leaving = true;
    emit(state.copyWith(phase: MeetingPhase.left));
    try {
      await _room?.disconnect();
    } catch (_) {}
    try {
      await services.meetings.leave(meetingId);
    } on ApiException {
      // Attendance is not worth blocking the exit for; the room's own event tells
      // meetsvc as well.
    }
    await WakelockPlus.disable();
  }

  Future<String> endForEveryone() async {
    try {
      await services.meetings.end(meetingId);
      _leaving = true;
      emit(
        state.copyWith(
          phase: MeetingPhase.ended,
          message: 'You ended the meeting.',
        ),
      );
      try {
        await _room?.disconnect();
      } catch (_) {}
      await WakelockPlus.disable();
      return '';
    } on ApiException catch (e) {
      return e.message;
    }
  }

  // ── the meetsvc socket ─────────────────────────────────────────────────────

  void _onSocketFrame(SocketFrame frame) {
    if (isClosed) return;
    if (frame.str('meeting_id') != meetingId) return;

    switch (frame.type) {
      case 'meeting.lobby':
        final me = services.session.caller?.profileId ?? '';
        if (frame.data['waiting'] == true) {
          if (!state.canHost) return;
          Sounds.knock();
          _loadLobby();
          return;
        }
        // A decision. The knocker learns from this frame that they were refused,
        // which is a truer sentence than the disconnect that follows it.
        if (frame.str('profile_id') == me &&
            frame.data['admitted'] == false &&
            state.phase == MeetingPhase.waiting) {
          emit(
            state.copyWith(
              phase: MeetingPhase.denied,
              message: 'The host did not let you in.',
            ),
          );
          return;
        }
        if (state.canHost) _loadLobby();
      case 'meeting.ended':
        if (state.isOver) return;
        emit(
          state.copyWith(
            phase: MeetingPhase.ended,
            message: 'The meeting ended.',
          ),
        );
    }
  }

  @override
  Future<void> close() async {
    _leaving = true;
    await _frames.cancel();
    await _listener?.dispose();
    try {
      await _room?.disconnect();
    } catch (_) {}
    try {
      await _room?.dispose();
    } catch (_) {}
    await _prepared.dispose();
    await WakelockPlus.disable();
    await _notices.close();
    return super.close();
  }
}
