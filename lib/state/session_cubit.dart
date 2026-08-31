import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import 'services.dart';

enum SessionStatus { unknown, signedOut, signedIn, unreachable }

class SessionState {
  const SessionState({
    required this.status,
    this.caller,
    this.notice = '',
    this.trouble = Trouble.failed,
  });

  final SessionStatus status;
  final Caller? caller;
  final String notice;

  /// Only read when [status] is [SessionStatus.unreachable]: it decides whether the
  /// splash asks the member to turn their data on or tells them we are the ones who
  /// cannot be reached.
  final Trouble trouble;

  SessionState copyWith({
    SessionStatus? status,
    Caller? caller,
    String? notice,
    Trouble? trouble,
  }) => SessionState(
    status: status ?? this.status,
    caller: caller ?? this.caller,
    notice: notice ?? this.notice,
    trouble: trouble ?? this.trouble,
  );
}

class SessionCubit extends Cubit<SessionState> {
  SessionCubit(this.services)
      : super(const SessionState(status: SessionStatus.unknown)) {
    _lost = services.sessionLost.listen((_) {
      emit(
        const SessionState(
          status: SessionStatus.signedOut,
          notice: 'Your session expired. Please sign in again.',
        ),
      );
    });
  }

  final AppServices services;
  late final StreamSubscription<void> _lost;

  /// How long the splash waits on the one request a launch cannot go on without before it
  /// stops looking like a launch and starts looking like a hang.
  ///
  /// Only reached when there is no cached caller, because with one the app is already at
  /// Home while this runs. Without one there is nothing to draw until it answers, and the
  /// request's own patience is twelve seconds — twelve seconds of splash with no sentence
  /// on it whenever we are the ones who are down.
  static const _launchPatience = Duration(seconds: 5);

  Timer? _launch;

  Future<void> bootstrap() async {
    if (!services.session.hasSession) {
      emit(const SessionState(status: SessionStatus.signedOut));
      return;
    }
    final cached = services.session.caller;
    if (cached != null) {
      emit(SessionState(status: SessionStatus.signedIn, caller: cached));
      services.socket.start();
      await refreshCaller(silent: true);
      return;
    }

    final probe = refreshCaller();
    // The probe is left running rather than abandoned: it still emits signedIn if it
    // lands after this, and a member reading the sentence is then simply taken past it.
    _launch = Timer(_launchPatience, () {
      if (isClosed || state.status != SessionStatus.unknown) return;
      emit(
        SessionState(
          status: SessionStatus.unreachable,
          trouble: services.reach.hasTransport
              ? Trouble.unreachable
              : Trouble.offline,
        ),
      );
    });
    await probe;
    _launch?.cancel();
  }

  Future<void> refreshCaller({bool silent = false}) async {
    try {
      final caller = await services.meet.me();
      await services.session.saveCaller(caller);
      emit(SessionState(status: SessionStatus.signedIn, caller: caller));
      services.socket.start();
    } on ApiException catch (e) {
      if (e.isUnauthorized || e.isForbidden) {
        await signOut();
        return;
      }
      if (silent) return;
      final cached = services.session.caller;
      if (cached != null) {
        emit(SessionState(status: SessionStatus.signedIn, caller: cached));
        services.socket.start();
      } else {
        emit(
          SessionState(
            status: SessionStatus.unreachable,
            notice: e.message,
            trouble: e.trouble,
          ),
        );
      }
    }
  }

  Future<void> adopt({
    required String token,
    required String refreshToken,
  }) async {
    await services.session.saveTokens(token: token, refreshToken: refreshToken);
    await refreshCaller();
  }

  Future<void> signOut() async {
    await services.signOut();
    emit(const SessionState(status: SessionStatus.signedOut));
  }

  @override
  Future<void> close() async {
    _launch?.cancel();
    await _lost.cancel();
    return super.close();
  }
}
