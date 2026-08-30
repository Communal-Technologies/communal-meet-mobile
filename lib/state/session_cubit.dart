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
  });

  final SessionStatus status;
  final Caller? caller;
  final String notice;

  SessionState copyWith({
    SessionStatus? status,
    Caller? caller,
    String? notice,
  }) => SessionState(
    status: status ?? this.status,
    caller: caller ?? this.caller,
    notice: notice ?? this.notice,
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

  Future<void> bootstrap() async {
    if (!services.session.hasSession) {
      emit(const SessionState(status: SessionStatus.signedOut));
      return;
    }
    final cached = services.session.caller;
    if (cached != null) {
      emit(SessionState(status: SessionStatus.signedIn, caller: cached));
      services.socket.start();
    }
    await refreshCaller(silent: cached != null);
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
          SessionState(status: SessionStatus.unreachable, notice: e.message),
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
    await _lost.cancel();
    return super.close();
  }
}
