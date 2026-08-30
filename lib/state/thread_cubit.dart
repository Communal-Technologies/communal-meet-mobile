import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../data/api_client.dart';
import '../data/local_store.dart';
import '../data/models.dart';
import '../data/socket.dart';
import 'conversations_cubit.dart';
import 'services.dart';

class ThreadState {
  const ThreadState({
    required this.conversation,
    this.messages = const [],
    this.pending = const [],
    this.loading = true,
    this.loadingOlder = false,
    this.hasOlder = true,
    this.error = '',
    this.trouble = Trouble.failed,
    this.typing = const [],
    this.readUpTo = 0,
  });

  final Conversation conversation;
  final List<Message> messages;
  final List<Message> pending;
  final bool loading;
  final bool loadingOlder;
  final bool hasOlder;
  final String error;
  final Trouble trouble;
  final List<String> typing;
  final int readUpTo;

  bool get isEmpty => messages.isEmpty && pending.isEmpty;

  ThreadState copyWith({
    Conversation? conversation,
    List<Message>? messages,
    List<Message>? pending,
    bool? loading,
    bool? loadingOlder,
    bool? hasOlder,
    String? error,
    Trouble? trouble,
    List<String>? typing,
    int? readUpTo,
  }) => ThreadState(
    conversation: conversation ?? this.conversation,
    messages: messages ?? this.messages,
    pending: pending ?? this.pending,
    loading: loading ?? this.loading,
    loadingOlder: loadingOlder ?? this.loadingOlder,
    hasOlder: hasOlder ?? this.hasOlder,
    error: error ?? this.error,
    trouble: trouble ?? this.trouble,
    typing: typing ?? this.typing,
    readUpTo: readUpTo ?? this.readUpTo,
  );
}

class ThreadCubit extends Cubit<ThreadState> {
  ThreadCubit(this.services, this.conversations, Conversation conversation)
      : super(
          ThreadState(
            conversation: conversation,
            readUpTo: conversation.othersReadSeq,
          ),
        ) {
    _frames = services.socket.frames.listen(_onFrame);
    _status = services.socket.status.listen((s) {
      if (s == SocketStatus.live) _catchUp();
    });
    _prune = Timer.periodic(const Duration(seconds: 2), (_) => _pruneTyping());
    conversations.openThread(conversation.id);
  }

  final AppServices services;
  final ConversationsCubit conversations;

  static const _pageSize = 40;
  static const _uuid = Uuid();

  late final StreamSubscription<SocketFrame> _frames;
  late final StreamSubscription<SocketStatus> _status;
  late final Timer _prune;

  final Map<String, DateTime> _typing = {};
  DateTime? _typingSentAt;
  bool _typingOn = false;

  String get _id => state.conversation.id;
  String get _me => services.session.caller?.profileId ?? '';

  Future<void> load() async {
    final cached = await services.store.messages(_id);
    final queued = await services.store.pending(conversationId: _id);
    if (cached.isNotEmpty || queued.isNotEmpty) {
      emit(
        state.copyWith(
          messages: cached,
          pending: _asMessages(queued),
          loading: false,
        ),
      );
    }
    _refreshReadPointer();
    try {
      final page = await services.chat.messages(_id, limit: _pageSize);
      await services.store.putMessages(_id, page);
      final merged = _merge(state.messages, page);
      emit(
        state.copyWith(
          messages: merged,
          loading: false,
          error: '',
          trouble: Trouble.failed,
          hasOlder: page.length >= _pageSize,
        ),
      );
      _flush();
      markRead();
    } on ApiException catch (e) {
      emit(
        state.copyWith(
          loading: false,
          error: state.messages.isEmpty ? e.message : '',
          trouble: e.trouble,
        ),
      );
    }
  }

  Future<void> loadOlder() async {
    if (state.loadingOlder || !state.hasOlder || state.messages.isEmpty) return;
    emit(state.copyWith(loadingOlder: true));
    try {
      final page = await services.chat.messages(
        _id,
        before: state.messages.first.seq,
        limit: _pageSize,
      );
      await services.store.putMessages(_id, page);
      emit(
        state.copyWith(
          messages: _merge(state.messages, page),
          loadingOlder: false,
          hasOlder: page.length >= _pageSize,
        ),
      );
    } on ApiException {
      emit(state.copyWith(loadingOlder: false));
    }
  }

  Future<void> send(String text) async {
    final body = text.trim();
    if (body.isEmpty) return;
    await _setTyping(false);
    final pending = PendingSend(
      clientMsgId: _uuid.v4(),
      conversationId: _id,
      body: body,
      replyToId: '',
      createdAt: DateTime.now(),
      failed: false,
    );
    await services.store.enqueue(pending);
    emit(
      state.copyWith(pending: [...state.pending, _asMessage(pending)]),
    );
    await _deliver(pending);
  }

  Future<void> retry(String clientMsgId) async {
    final queued = await services.store.pending(conversationId: _id);
    final one = queued.where((p) => p.clientMsgId == clientMsgId).firstOrNull;
    if (one == null) return;
    await services.store.markFailed(clientMsgId, false);
    emit(state.copyWith(pending: _asMessages(await _reloadPending())));
    await _deliver(one);
  }

  Future<void> discard(String clientMsgId) async {
    await services.store.dequeue(clientMsgId);
    emit(state.copyWith(pending: _asMessages(await _reloadPending())));
  }

  // Read receipts arrive on the socket, so a thread opened cold knows nothing about
  // what the other side read before the app was running. The conversation carries
  // their pointer; this asks for a current one rather than trusting the list's copy.
  Future<void> _refreshReadPointer() async {
    try {
      final fresh = await services.chat.conversation(_id);
      if (isClosed) return;
      state.conversation.othersReadSeq = fresh.othersReadSeq;
      if (fresh.othersReadSeq > state.readUpTo) {
        emit(state.copyWith(readUpTo: fresh.othersReadSeq));
      }
    } on ApiException {
      // Ticks are not worth a retry of their own; the next frame or open corrects it.
    }
  }

  Future<void> markRead() async {
    final seq = state.messages.isEmpty ? 0 : state.messages.last.seq;
    conversations.markLocallyRead(_id);
    if (seq <= 0) return;
    try {
      await services.chat.markRead(_id, seq: seq);
    } on ApiException {
      services.socket.sendRead(_id, seq);
    }
  }

  void composerChanged(String text) {
    final on = text.trim().isNotEmpty;
    if (!on) {
      if (_typingOn) _setTyping(false);
      return;
    }
    final last = _typingSentAt;
    if (_typingOn &&
        last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 4)) {
      return;
    }
    _setTyping(true);
  }

  Future<void> mute(int minutes) async {
    try {
      final until = await services.chat.mute(_id, minutes);
      state.conversation.mutedUntil = until;
      emit(state.copyWith(conversation: state.conversation));
      conversations.upsert(state.conversation);
    } on ApiException {
      // A mute that did not land is retried by the next tap.
    }
  }

  Future<void> setPostingPolicy(String policy) async {
    final applied = await services.chat.setPostingPolicy(_id, policy);
    state.conversation.postingPolicy = applied;
    state.conversation.canPost =
        applied == 'all_members' || state.conversation.isAdmin;
    emit(state.copyWith(conversation: state.conversation));
    conversations.upsert(state.conversation);
  }

  Future<void> _deliver(PendingSend pending) async {
    try {
      final stored = await services.chat.send(
        _id,
        body: pending.body,
        clientMsgId: pending.clientMsgId,
        replyToId: pending.replyToId,
      );
      await services.store.dequeue(pending.clientMsgId);
      await services.store.putMessages(_id, [stored]);
      emit(
        state.copyWith(
          messages: _merge(state.messages, [stored]),
          pending: state.pending
              .where((m) => m.clientMsgId != pending.clientMsgId)
              .toList(),
        ),
      );
    } on ApiException catch (e) {
      if (!e.isOffline) await services.store.markFailed(pending.clientMsgId, true);
      emit(
        state.copyWith(
          pending: _asMessages(await _reloadPending()),
          trouble: e.trouble,
        ),
      );
    }
  }

  Future<void> _flush() async {
    for (final queued in await services.store.pending(conversationId: _id)) {
      if (queued.failed) continue;
      await _deliver(queued);
    }
  }

  Future<List<PendingSend>> _reloadPending() =>
      services.store.pending(conversationId: _id);

  Future<void> _catchUp() async {
    if (state.messages.isEmpty) {
      await load();
      return;
    }
    try {
      final page = await services.chat.messages(
        _id,
        after: state.messages.last.seq,
        limit: 100,
      );
      if (page.isEmpty) return;
      await services.store.putMessages(_id, page);
      emit(state.copyWith(messages: _merge(state.messages, page)));
      markRead();
    } on ApiException {
      // The socket will report live again and this will be retried.
    }
  }

  Future<void> _setTyping(bool on) async {
    _typingOn = on;
    _typingSentAt = on ? DateTime.now() : null;
    services.socket.sendTyping(_id, on);
  }

  void _onFrame(SocketFrame frame) {
    switch (frame.type) {
      case 'message.new':
        final message = Message.fromJson(frame.data);
        if (message.conversationId != _id) return;
        _typing.remove(message.senderProfileId);
        services.store.putMessages(_id, [message]);
        emit(
          state.copyWith(
            messages: _merge(state.messages, [message]),
            pending: message.clientMsgId.isEmpty
                ? state.pending
                : state.pending
                    .where((m) => m.clientMsgId != message.clientMsgId)
                    .toList(),
            typing: _typingNames(),
          ),
        );
        if (message.senderProfileId != _me) markRead();
        break;
      case 'message.read':
        if (frame.str('conversation_id') != _id) return;
        if (frame.str('profile_id') == _me) return;
        final seq = int.tryParse(frame.str('seq')) ?? 0;
        if (seq > state.readUpTo) emit(state.copyWith(readUpTo: seq));
        break;
      case 'typing':
        if (frame.str('conversation_id') != _id) return;
        final who = frame.str('profile_id');
        if (who.isEmpty || who == _me) return;
        final name = frame.str('name');
        if (frame.data['typing'] == false) {
          _typing.remove(name.isEmpty ? who : name);
        } else {
          _typing[name.isEmpty ? who : name] = DateTime.now();
        }
        emit(state.copyWith(typing: _typingNames()));
        break;
    }
  }

  void _pruneTyping() {
    if (_typing.isEmpty) return;
    final now = DateTime.now();
    final before = _typing.length;
    _typing.removeWhere((_, at) => now.difference(at).inSeconds > 6);
    if (_typing.length != before) emit(state.copyWith(typing: _typingNames()));
  }

  List<String> _typingNames() => _typing.keys.toList();

  Message _asMessage(PendingSend pending) => pending.asMessage(
    _me,
    services.session.caller?.name ?? '',
  );

  List<Message> _asMessages(List<PendingSend> list) =>
      list.map(_asMessage).toList();

  static List<Message> _merge(List<Message> current, List<Message> incoming) {
    final byId = {for (final m in current) m.id: m};
    for (final m in incoming) {
      byId[m.id] = m;
    }
    final out = byId.values.toList();
    out.sort((a, b) => a.seq.compareTo(b.seq));
    return out;
  }

  @override
  Future<void> close() async {
    conversations.closeThread(_id);
    if (_typingOn) services.socket.sendTyping(_id, false);
    _prune.cancel();
    await _frames.cancel();
    await _status.cancel();
    return super.close();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
