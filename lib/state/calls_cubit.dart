import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../data/socket.dart';
import 'services.dart';

class CallsState {
  const CallsState({
    this.items = const [],
    this.loading = true,
    this.error = '',
    this.trouble = Trouble.failed,
  });

  final List<CallRecord> items;
  final bool loading;
  final String error;
  final Trouble trouble;

  bool get isEmpty => items.isEmpty;

  CallsState copyWith({
    List<CallRecord>? items,
    bool? loading,
    String? error,
    Trouble? trouble,
  }) => CallsState(
    items: items ?? this.items,
    loading: loading ?? this.loading,
    error: error ?? this.error,
    trouble: trouble ?? this.trouble,
  );
}

/// The call history, refreshed whenever a call on this device finishes.
class CallsCubit extends Cubit<CallsState> {
  CallsCubit(this.services) : super(const CallsState()) {
    _frames = services.socket.frames.listen((frame) {
      if (frame.type == 'call.ring' ||
          frame.type == 'call.cancelled' ||
          frame.type == 'call.answered') {
        refresh();
      }
    });
  }

  final AppServices services;
  late final StreamSubscription<SocketFrame> _frames;

  Future<void> load() => _fetch(initial: true);

  Future<void> refresh() => _fetch(initial: false);

  Future<void> _fetch({required bool initial}) async {
    if (initial) emit(state.copyWith(loading: true));
    try {
      final calls = await services.calls.recent();
      if (isClosed) return;
      emit(CallsState(items: calls, loading: false));
    } on ApiException catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(loading: false, error: e.message, trouble: e.trouble),
      );
    }
  }

  @override
  Future<void> close() async {
    await _frames.cancel();
    return super.close();
  }
}
