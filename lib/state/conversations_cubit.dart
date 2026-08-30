import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../data/socket.dart';
import 'services.dart';

class ConversationsState {
  const ConversationsState({
    this.items = const [],
    this.loading = true,
    this.refreshing = false,
    this.error = '',
    this.offline = false,
  });

  final List<Conversation> items;
  final bool loading;
  final bool refreshing;
  final String error;
  final bool offline;

  bool get isEmpty => items.isEmpty;

  ConversationsState copyWith({
    List<Conversation>? items,
    bool? loading,
    bool? refreshing,
    String? error,
    bool? offline,
  }) => ConversationsState(
    items: items ?? this.items,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    error: error ?? this.error,
    offline: offline ?? this.offline,
  );
}

class ConversationsCubit extends Cubit<ConversationsState> {
  ConversationsCubit(this.services) : super(const ConversationsState()) {
    _frames = services.socket.frames.listen(_onFrame);
    _status = services.socket.status.listen((s) {
      if (s == SocketStatus.live) refresh();
    });
  }

  final AppServices services;
  late final StreamSubscription<SocketFrame> _frames;
  late final StreamSubscription<SocketStatus> _status;

  String _activeId = '';

  void openThread(String id) => _activeId = id;
  void closeThread(String id) {
    if (_activeId == id) _activeId = '';
  }

  Future<void> load() async {
    final cached = await services.store.conversations();
    if (cached.isNotEmpty) {
      emit(state.copyWith(items: cached, loading: false, refreshing: true));
    }
    await refresh();
  }

  Future<void> refresh() async {
    if (state.items.isNotEmpty) emit(state.copyWith(refreshing: true));
    try {
      final list = await services.chat.conversations();
      _sort(list);
      await services.store.putConversations(list);
      emit(
        ConversationsState(
          items: list,
          loading: false,
          refreshing: false,
        ),
      );
    } on ApiException catch (e) {
      emit(
        state.copyWith(
          loading: false,
          refreshing: false,
          error: state.items.isEmpty ? e.message : '',
          offline: e.isOffline,
        ),
      );
    }
  }

  void markLocallyRead(String id) {
    final index = state.items.indexWhere((c) => c.id == id);
    if (index < 0 || state.items[index].unread == 0) return;
    final list = [...state.items];
    list[index].unread = 0;
    emit(state.copyWith(items: list));
    services.store.putConversations(list);
  }

  void upsert(Conversation conversation) {
    final list = [...state.items];
    final index = list.indexWhere((c) => c.id == conversation.id);
    if (index >= 0) {
      list[index] = conversation;
    } else {
      list.insert(0, conversation);
    }
    _sort(list);
    emit(state.copyWith(items: list, loading: false));
    services.store.putConversations(list);
  }

  void _onFrame(SocketFrame frame) {
    switch (frame.type) {
      case 'message.new':
        _applyNew(Message.fromJson(frame.data));
        break;
      case 'message.read':
        if (frame.str('profile_id') == services.session.caller?.profileId) {
          markLocallyRead(frame.str('conversation_id'));
        }
        break;
      case 'conversation.updated':
        _applyPolicy(frame);
        break;
    }
  }

  void _applyNew(Message message) {
    final index = state.items.indexWhere((c) => c.id == message.conversationId);
    if (index < 0) {
      refresh();
      return;
    }
    final list = [...state.items];
    final row = list[index];
    row.lastMessageAt = message.createdAt;
    row.lastMessagePreview = message.body;
    row.lastMessageSeq = message.seq;
    final mine = message.senderProfileId == services.session.caller?.profileId;
    if (!mine && _activeId != row.id) row.unread += 1;
    _sort(list);
    emit(state.copyWith(items: list));
    services.store.putConversations(list);
  }

  void _applyPolicy(SocketFrame frame) {
    final id = frame.str('conversation_id');
    final policy = frame.str('posting_policy');
    final index = state.items.indexWhere((c) => c.id == id);
    if (index < 0 || policy.isEmpty) return;
    final list = [...state.items];
    final row = list[index];
    row.postingPolicy = policy;
    if (policy == 'admins_only') row.canPost = row.isAdmin;
    if (policy == 'all_members') row.canPost = true;
    emit(state.copyWith(items: list));
    services.store.putConversations(list);
  }

  static void _sort(List<Conversation> list) {
    list.sort((a, b) {
      final x = a.lastMessageAt;
      final y = b.lastMessageAt;
      if (x == null && y == null) return a.displayName.compareTo(b.displayName);
      if (x == null) return 1;
      if (y == null) return -1;
      return y.compareTo(x);
    });
  }

  @override
  Future<void> close() async {
    await _frames.cancel();
    await _status.cancel();
    return super.close();
  }
}
