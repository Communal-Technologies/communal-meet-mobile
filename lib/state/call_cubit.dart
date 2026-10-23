import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/sounds.dart';
import '../data/models.dart';
import '../data/socket.dart';
import 'services.dart';

enum CallPhase { connecting, ringing, live, ended, failed }

class CallState {
  const CallState({
    required this.call,
    required this.phase,
    this.micOn = true,
    this.cameraOn = true,
    this.speakerOn = true,
    this.remote,
    this.local,
    this.notice = '',
    this.seconds = 0,
  });

  final CallRecord call;
  final CallPhase phase;
  final bool micOn;
  final bool cameraOn;
  final bool speakerOn;
  final RemoteParticipant? remote;
  final LocalParticipant? local;
  final String notice;
  final int seconds;

  bool get isOver => phase == CallPhase.ended || phase == CallPhase.failed;

  CallState copyWith({
    CallRecord? call,
    CallPhase? phase,
    bool? micOn,
    bool? cameraOn,
    bool? speakerOn,
    RemoteParticipant? remote,
    bool clearRemote = false,
    LocalParticipant? local,
    String? notice,
    int? seconds,
  }) => CallState(
    call: call ?? this.call,
    phase: phase ?? this.phase,
    micOn: micOn ?? this.micOn,
    cameraOn: cameraOn ?? this.cameraOn,
    speakerOn: speakerOn ?? this.speakerOn,
    remote: clearRemote ? null : (remote ?? this.remote),
    local: local ?? this.local,
    notice: notice ?? this.notice,
    seconds: seconds ?? this.seconds,
  );
}

/// Drives one 1:1 call: the room, the two participants, and the clock.
class CallCubit extends Cubit<CallState> {
  CallCubit(this.services, this.ticket, {required this.outgoing})
    : super(
        CallState(
          call: ticket.call,
          phase: outgoing ? CallPhase.ringing : CallPhase.connecting,
          cameraOn: ticket.call.video,
        ),
      );

  final AppServices services;
  final CallTicket ticket;
  final bool outgoing;

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  StreamSubscription<SocketFrame>? _frames;
  Timer? _clock;
  bool _finished = false;

  Future<void> start() async {
    _frames = services.socket.frames.listen(_onFrame);
    if (outgoing) Sounds.ringback();

    final room = Room(
      roomOptions: RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultVideoPublishOptions: const VideoPublishOptions(simulcast: false),
      ),
    );
    _room = room;
    final listener = room.createListener();
    _listener = listener;
    _wire(listener);

    final ice = [
      for (final server in ticket.iceServers)
        RTCIceServer(
          urls: server.urls,
          username: server.username,
          credential: server.credential,
        ),
    ];

    try {
      await room.connect(
        ticket.livekitUrl,
        ticket.token,
        connectOptions: ice.isEmpty
            ? const ConnectOptions()
            : ConnectOptions(
                rtcConfiguration: RTCConfiguration(iceServers: ice),
              ),
      );
      await WakelockPlus.enable();
      final local = room.localParticipant;
      if (local != null) {
        await local.setMicrophoneEnabled(true);
        await local.setCameraEnabled(ticket.call.video);
      }
      if (isClosed) return;
      emit(state.copyWith(local: local));
      _adoptRemote();
    } catch (error, stack) {
      debugPrint('Meet could not join the call room: $error\n$stack');
      if (!isClosed) {
        emit(
          state.copyWith(
            phase: CallPhase.failed,
            notice: 'We could not connect that call. Try again.',
          ),
        );
      }
    }
  }

  void _wire(EventsListener<RoomEvent> listener) {
    listener
      ..on<ParticipantConnectedEvent>((_) => _adoptRemote())
      ..on<ParticipantDisconnectedEvent>((_) {
        if (state.phase == CallPhase.live) {
          _settle(CallPhase.ended, 'Call ended.');
        } else {
          _adoptRemote();
        }
      })
      ..on<TrackSubscribedEvent>((_) => _adoptRemote())
      ..on<TrackUnsubscribedEvent>((_) => _adoptRemote())
      ..on<RoomDisconnectedEvent>(
        (_) => _settle(CallPhase.ended, 'Call ended.'),
      );
  }

  void _adoptRemote() {
    final room = _room;
    if (room == null || isClosed) return;
    final remote = room.remoteParticipants.values.isEmpty
        ? null
        : room.remoteParticipants.values.first;
    if (remote == null) {
      emit(state.copyWith(clearRemote: true));
      return;
    }
    if (state.phase != CallPhase.live) Sounds.stopRingback();
    emit(state.copyWith(remote: remote, phase: CallPhase.live));
    _startClock();
  }

  void _startClock() {
    _clock ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (isClosed) return;
      emit(state.copyWith(seconds: state.seconds + 1));
    });
  }

  void _onFrame(SocketFrame frame) {
    final id = (frame.data['id'] ?? '').toString();
    if (id.isNotEmpty && id != state.call.id) return;
    switch (frame.type) {
      case 'call.answered':
        _adoptRemote();
      case 'call.cancelled':
        final status = (frame.data['status'] ?? '').toString();
        _settle(
          CallPhase.ended,
          status == 'declined' ? 'Call declined.' : 'Call ended.',
        );
      default:
        break;
    }
  }

  Future<void> toggleMic() async {
    final want = !state.micOn;
    emit(state.copyWith(micOn: want));
    try {
      await state.local?.setMicrophoneEnabled(want);
    } catch (_) {
      if (!isClosed) emit(state.copyWith(micOn: !want));
    }
  }

  Future<void> toggleCamera() async {
    final want = !state.cameraOn;
    emit(state.copyWith(cameraOn: want));
    try {
      await state.local?.setCameraEnabled(want);
    } catch (_) {
      if (!isClosed) emit(state.copyWith(cameraOn: !want));
    }
  }

  Future<void> toggleSpeaker() async {
    final want = !state.speakerOn;
    emit(state.copyWith(speakerOn: want));
    try {
      await AudioManager.instance.setSpeakerOutputPreferred(want);
    } catch (_) {
      if (!isClosed) emit(state.copyWith(speakerOn: !want));
    }
  }

  /// Hangs up, and ends the call on the backend.
  Future<void> hangUp() async {
    if (_finished) return;
    _finished = true;
    try {
      await services.calls.end(state.call.id);
    } catch (e) {
      debugPrint('Meet could not end the call cleanly: $e');
    }
    _settle(CallPhase.ended, 'Call ended.');
  }

  void _settle(CallPhase phase, String notice) {
    if (isClosed || state.isOver) return;
    Sounds.stopRingback();
    _clock?.cancel();
    _clock = null;
    emit(state.copyWith(phase: phase, notice: notice));
  }

  @override
  Future<void> close() async {
    Sounds.stopRingback();
    _clock?.cancel();
    await _frames?.cancel();
    await _listener?.dispose();
    await _disconnect();
    await _room?.dispose();
    await WakelockPlus.disable();
    return super.close();
  }

  Future<void> _disconnect() async {
    try {
      await _room?.disconnect();
    } catch (_) {
      return;
    }
  }
}
