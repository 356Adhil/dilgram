import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/memory_model.dart';
import '../../../services/api_service.dart';

final timelineProvider = StateNotifierProvider<TimelineNotifier, TimelineState>(
  (ref) {
    return TimelineNotifier(
      ref.read(apiServiceProvider),
      ref.read(cachedApiProvider),
    );
  },
);

class TimelineState {
  final List<Memory> memories;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int currentPage;
  final String? error;
  // Selection mode
  final Set<String> selectedIds;
  final bool isSelectionMode;
  // Search
  final String? searchQuery;
  final List<Memory>? searchResults;
  final bool isSearching;

  const TimelineState({
    this.memories = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.currentPage = 1,
    this.error,
    this.selectedIds = const {},
    this.isSelectionMode = false,
    this.searchQuery,
    this.searchResults,
    this.isSearching = false,
  });

  TimelineState copyWith({
    List<Memory>? memories,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? currentPage,
    String? error,
    Set<String>? selectedIds,
    bool? isSelectionMode,
    String? searchQuery,
    List<Memory>? searchResults,
    bool? isSearching,
    bool clearSearch = false,
  }) {
    return TimelineState(
      memories: memories ?? this.memories,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      error: error,
      selectedIds: selectedIds ?? this.selectedIds,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
      searchQuery: clearSearch ? null : (searchQuery ?? this.searchQuery),
      searchResults: clearSearch ? null : (searchResults ?? this.searchResults),
      isSearching: isSearching ?? this.isSearching,
    );
  }
}

class TimelineNotifier extends StateNotifier<TimelineState> {
  final ApiService _api;
  final CachedApiService _cached;

  TimelineNotifier(this._api, this._cached) : super(const TimelineState()) {
    loadMemories();
  }

  Future<void> loadMemories() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, error: null);

    try {
      final data = await _cached.getMemories(
        page: 1,
        limit: 20,
        onFresh: (freshData) {
          if (!mounted) return;
          final memories = freshData
              .map((e) => Memory.fromJson(e as Map<String, dynamic>))
              .toList();
          state = state.copyWith(
            memories: memories,
            currentPage: 1,
            hasMore: memories.length >= 20,
          );
        },
      );
      if (data != null) {
        final memories = data
            .map((e) => Memory.fromJson(e as Map<String, dynamic>))
            .toList();
        state = state.copyWith(
          memories: memories,
          isLoading: false,
          currentPage: 1,
          hasMore: memories.length >= 20,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'Failed to load memories',
        );
      }
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
      final data = await _cached.getMemories(page: nextPage, limit: 20);
      final newMemories = (data ?? [])
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
    _cached.invalidateTimeline();
  }

  void removeMemory(String id) {
    state = state.copyWith(
      memories: state.memories.where((m) => m.id != id).toList(),
    );
    _cached.invalidateTimeline();
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

  // Favorites
  Future<void> toggleFavorite(String id) async {
    try {
      final result = await _api.toggleFavorite(id);
      final isFav = result['isFavorite'] as bool;
      state = state.copyWith(
        memories: state.memories
            .map((m) => m.id == id ? m.copyWith(isFavorite: isFav) : m)
            .toList(),
      );
    } catch (_) {}
  }

  // Selection mode
  void toggleSelectionMode() {
    if (state.isSelectionMode) {
      state = state.copyWith(isSelectionMode: false, selectedIds: {});
    } else {
      state = state.copyWith(isSelectionMode: true);
    }
  }

  void toggleSelection(String id) {
    final updated = Set<String>.from(state.selectedIds);
    if (updated.contains(id)) {
      updated.remove(id);
    } else {
      updated.add(id);
    }
    state = state.copyWith(
      selectedIds: updated,
      isSelectionMode: updated.isNotEmpty,
    );
  }

  void selectAll() {
    state = state.copyWith(
      selectedIds: state.memories.map((m) => m.id).toSet(),
      isSelectionMode: true,
    );
  }

  void clearSelection() {
    state = state.copyWith(selectedIds: {}, isSelectionMode: false);
  }

  Future<void> batchDelete() async {
    if (state.selectedIds.isEmpty) return;
    try {
      final ids = state.selectedIds.toList();
      await _api.batchDeleteMemories(ids);
      state = state.copyWith(
        memories: state.memories
            .where((m) => !state.selectedIds.contains(m.id))
            .toList(),
        selectedIds: {},
        isSelectionMode: false,
      );
    } catch (_) {}
  }

  // Search
  Future<void> searchMemories(String query) async {
    if (query.trim().isEmpty) {
      state = state.copyWith(clearSearch: true);
      return;
    }
    state = state.copyWith(searchQuery: query, isSearching: true);
    try {
      final data = await _api.searchMemories(query);
      final results = data
          .map((e) => Memory.fromJson(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(searchResults: results, isSearching: false);
    } catch (_) {
      state = state.copyWith(isSearching: false);
    }
  }

  void clearSearch() {
    state = state.copyWith(clearSearch: true);
  }
}
