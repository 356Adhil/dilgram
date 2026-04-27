import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/memory_model.dart';
import '../../../services/api_service.dart';

final timelineProvider = StateNotifierProvider<TimelineNotifier, TimelineState>(
  (ref) {
    return TimelineNotifier(ref.read(apiServiceProvider));
  },
);

class TimelineState {
  final List<Memory> memories;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int currentPage;
  final String? error;

  const TimelineState({
    this.memories = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.currentPage = 1,
    this.error,
  });

  TimelineState copyWith({
    List<Memory>? memories,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? currentPage,
    String? error,
  }) {
    return TimelineState(
      memories: memories ?? this.memories,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      error: error,
    );
  }
}

class TimelineNotifier extends StateNotifier<TimelineState> {
  final ApiService _api;

  TimelineNotifier(this._api) : super(const TimelineState()) {
    loadMemories();
  }

  Future<void> loadMemories() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, error: null);

    try {
      final data = await _api.getMemories(page: 1, limit: 20);
      final memories = data
          .map((e) => Memory.fromJson(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(
        memories: memories,
        isLoading: false,
        currentPage: 1,
        hasMore: memories.length >= 20,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load memories',
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);

    try {
      final nextPage = state.currentPage + 1;
      final data = await _api.getMemories(page: nextPage, limit: 20);
      final newMemories = data
          .map((e) => Memory.fromJson(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(
        memories: [...state.memories, ...newMemories],
        isLoadingMore: false,
        currentPage: nextPage,
        hasMore: newMemories.length >= 20,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(error: null);
    await loadMemories();
  }

  void addMemory(Memory memory) {
    state = state.copyWith(memories: [memory, ...state.memories]);
  }

  void removeMemory(String id) {
    state = state.copyWith(
      memories: state.memories.where((m) => m.id != id).toList(),
    );
  }

  void updateMemory(Memory memory) {
    state = state.copyWith(
      memories: state.memories
          .map((m) => m.id == memory.id ? memory : m)
          .toList(),
    );
  }

  Memory? getMemoryById(String id) {
    try {
      return state.memories.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }
}
