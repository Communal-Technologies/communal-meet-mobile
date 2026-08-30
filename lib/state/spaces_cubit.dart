import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import 'services.dart';

class SpacesState {
  const SpacesState({
    this.items = const [],
    this.loading = true,
    this.error = '',
    this.trouble = Trouble.failed,
  });

  final List<Space> items;
  final bool loading;
  final String error;
  final Trouble trouble;

  SpacesState copyWith({
    List<Space>? items,
    bool? loading,
    String? error,
    Trouble? trouble,
  }) => SpacesState(
    items: items ?? this.items,
    loading: loading ?? this.loading,
    error: error ?? this.error,
    trouble: trouble ?? this.trouble,
  );
}

class SpacesCubit extends Cubit<SpacesState> {
  SpacesCubit(this.services) : super(const SpacesState());

  final AppServices services;

  Future<void> load() async {
    if (state.items.isEmpty) emit(state.copyWith(loading: true, error: ''));
    try {
      final list = await services.meet.spaces();
      emit(SpacesState(items: list, loading: false));
    } on ApiException catch (e) {
      emit(
        state.copyWith(
          loading: false,
          error: state.items.isEmpty ? e.message : '',
          trouble: e.trouble,
        ),
      );
    }
  }
}
