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
  }

  final SessionStore session;
  final LocalStore store;
  final Reachability reach;

  late final ApiClient api;
  late final MeetSocket socket;
  late final AuthRepository auth;
  late final ChatRepository chat;
  late final MeetRepository meet;

  final _sessionLost = StreamController<void>.broadcast();
  Stream<void> get sessionLost => _sessionLost.stream;

  static Future<AppServices> boot() async {
    final session = SessionStore();
    await session.load();
    final store = LocalStore();
    await store.open();
    final reach = Reachability();
    await reach.start();
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
