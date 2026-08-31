import 'dart:async';

import '../core/reachability.dart';
import '../data/api_client.dart';
import '../data/local_store.dart';
import '../data/repositories.dart';
import '../data/session_store.dart';
import '../data/socket.dart';

class AppServices {
  AppServices._(this.session, this.store, this.reach) {
    api = ApiClient(
      session: session,
      onSessionLost: _onSessionLost,
      reach: reach,
    );
    socket = MeetSocket(session: session);
    auth = AuthRepository(api);
    chat = ChatRepository(api);
    meet = MeetRepository(api);
    meetings = MeetingsRepository(api);
  }

  final SessionStore session;
  final LocalStore store;
  final Reachability reach;

  late final ApiClient api;
  late final MeetSocket socket;
  late final AuthRepository auth;
  late final ChatRepository chat;
  late final MeetRepository meet;
  late final MeetingsRepository meetings;

  final _sessionLost = StreamController<void>.broadcast();
  Stream<void> get sessionLost => _sessionLost.stream;

  /// The three cold platform channels a launch cannot start without — the keystore, the
  /// database file and the connectivity plugin — and not one of them needs another's
  /// answer. Run one after another they were most of the wait before the first frame.
  static Future<AppServices> boot() async {
    final session = SessionStore();
    final store = LocalStore();
    final reach = Reachability();
    await Future.wait([session.load(), store.open(), reach.start()]);
    return AppServices._(session, store, reach);
  }

  Future<void> _onSessionLost() async {
    socket.stop();
    await session.clear();
    await store.wipe();
    if (!_sessionLost.isClosed) _sessionLost.add(null);
  }

  Future<void> signOut() async {
    socket.stop();
    await session.clear();
    await store.wipe();
  }
}
