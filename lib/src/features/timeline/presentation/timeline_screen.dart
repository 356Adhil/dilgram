import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../application/timeline_provider.dart';
import '../domain/memory_model.dart';
import '../../settings/application/theme_provider.dart';
import '../../../constants/app_strings.dart';
import 'widgets/memory_card.dart';
import 'widgets/empty_state_widget.dart';

class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  bool _showSearch = false;
  bool _showFavoritesOnly = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(timelineProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeline = ref.watch(timelineProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          if (timeline.isSelectionMode)
            _buildSelectionAppBar(theme, timeline)
          else
            _buildNormalAppBar(theme),
        ],
        body: RefreshIndicator(
          onRefresh: () => ref.read(timelineProvider.notifier).refresh(),
          color: theme.colorScheme.primary,
          child: _buildBody(timeline, theme),
        ),
      ),
    );
  }

  SliverAppBar _buildNormalAppBar(ThemeData theme) {
    return SliverAppBar(
      floating: true,
      snap: true,
      backgroundColor: theme.scaffoldBackgroundColor.withValues(alpha: 0.85),
      surfaceTintColor: Colors.transparent,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(color: Colors.transparent),
        ),
      ),
      title: _showSearch
          ? TextField(
              controller: _searchController,
              autofocus: true,
              style: GoogleFonts.inter(fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Search memories...',
                hintStyle: GoogleFonts.inter(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (q) {
                ref.read(timelineProvider.notifier).searchMemories(q);
              },
            )
          : Text(
              'Gallery',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
            ),
      actions: [
        if (_showSearch)
          IconButton(
            onPressed: () {
              setState(() => _showSearch = false);
              _searchController.clear();
              ref.read(timelineProvider.notifier).clearSearch();
            },
            icon: const Icon(Icons.close, size: 22),
          )
        else ...[
          IconButton(
            onPressed: () => setState(() => _showSearch = true),
            icon: const Icon(Icons.search_outlined, size: 22),
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.surfaceContainerHigh
                  .withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () {
              setState(() => _showFavoritesOnly = !_showFavoritesOnly);
              HapticFeedback.lightImpact();
            },
            icon: Icon(
              _showFavoritesOnly ? Icons.favorite : Icons.favorite_border,
              size: 22,
              color: _showFavoritesOnly
                  ? Colors.redAccent
                  : theme.colorScheme.onSurface,
            ),
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.surfaceContainerHigh
                  .withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () {
              ref.read(themeModeProvider.notifier).toggle();
              HapticFeedback.lightImpact();
            },
            icon: Icon(
              theme.brightness == Brightness.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              size: 22,
            ),
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.surfaceContainerHigh
                  .withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined, size: 22),
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.surfaceContainerHigh
                  .withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }

  SliverAppBar _buildSelectionAppBar(ThemeData theme, TimelineState timeline) {
    return SliverAppBar(
      floating: true,
      snap: true,
      pinned: true,
      backgroundColor: theme.colorScheme.primaryContainer.withValues(
        alpha: 0.95,
      ),
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        onPressed: () => ref.read(timelineProvider.notifier).clearSelection(),
        icon: const Icon(Icons.close),
      ),
      title: Text(
        '${timeline.selectedIds.length} selected',
        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
      ),
      actions: [
        IconButton(
          onPressed: () => ref.read(timelineProvider.notifier).selectAll(),
          icon: const Icon(Icons.select_all, size: 22),
          tooltip: 'Select all',
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: timeline.selectedIds.isEmpty
              ? null
              : () => _confirmBatchDelete(theme, timeline),
          icon: const Icon(Icons.delete_outline, size: 22),
          tooltip: 'Delete selected',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  void _confirmBatchDelete(ThemeData theme, TimelineState timeline) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete memories?'),
        content: Text(
          'Are you sure you want to delete ${timeline.selectedIds.length} memories? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(timelineProvider.notifier).batchDelete();
            },
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(TimelineState timeline, ThemeData theme) {
    // Show search results if searching
    if (timeline.searchResults != null) {
      if (timeline.isSearching) {
        return _buildLoadingShimmer(theme);
      }
      if (timeline.searchResults!.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off,
                size: 64,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'No results found',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        );
      }
      return _buildTimeline(
        timeline.copyWith(memories: timeline.searchResults),
        theme,
      );
    }

    if (timeline.isLoading && timeline.memories.isEmpty) {
      return _buildLoadingShimmer(theme);
    }
    if (timeline.error != null && timeline.memories.isEmpty) {
      return _buildErrorState(theme, timeline.error!);
    }

    // Apply favorites filter locally
    var displayState = timeline;
    if (_showFavoritesOnly) {
      final favs = timeline.memories.where((m) => m.isFavorite).toList();
      displayState = timeline.copyWith(memories: favs);
      if (favs.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.favorite_border,
                size: 64,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'No favorites yet',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        );
      }
    }

    if (displayState.memories.isEmpty) {
      return const EmptyStateWidget();
    }
    return _buildTimeline(displayState, theme);
  }

  Widget _buildTimeline(TimelineState timeline, ThemeData theme) {
    final grouped = _groupByDate(timeline.memories);
    final entries = grouped.entries.toList();

    // Track month changes for big section headers
    String? lastMonthKey;

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 120),
      itemCount: entries.length + (timeline.isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= entries.length) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          );
        }

        final entry = entries[index];

        // Determine month key from first memory in group
        final firstMemory = entry.value.first;
        final monthKey =
            '${firstMemory.createdAt.year}-${firstMemory.createdAt.month}';
        final showMonthHeader = monthKey != lastMonthKey;
        lastMonthKey = monthKey;

        String monthLabel;
        final now = DateTime.now();
        if (firstMemory.createdAt.year == now.year &&
            firstMemory.createdAt.month == now.month) {
          monthLabel = 'This Month';
        } else if (firstMemory.createdAt.year == now.year) {
          monthLabel = DateFormat('MMMM').format(firstMemory.createdAt);
        } else {
          monthLabel = DateFormat('MMMM yyyy').format(firstMemory.createdAt);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month section header
            if (showMonthHeader)
              Padding(
                padding: EdgeInsets.fromLTRB(16, index == 0 ? 8 : 28, 16, 4),
                child: Text(
                  monthLabel,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            // Date header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Text(
                entry.key,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            _buildMemoryGrid(entry.value, theme),
          ],
        );
      },
    );
  }

  Widget _buildMemoryGrid(List<Memory> memories, ThemeData theme) {
    // Dynamic grid: first 3 items can be larger
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: List.generate(memories.length, (index) {
          // Calculate item size — first row can have mixed sizes like reference
          final screenWidth = MediaQuery.of(context).size.width - 24; // padding
          final isFirstRow = index < 3 && memories.length >= 3;
          double itemSize;

          if (isFirstRow) {
            if (index == 0) {
              itemSize = (screenWidth - 8) * 0.33; // smaller
            } else if (index == 1) {
              itemSize = (screenWidth - 8) * 0.33; // medium
            } else {
              itemSize = (screenWidth - 8) * 0.33; // equal thirds
            }
          } else {
            // 3 columns for remaining
            itemSize = (screenWidth - 8) / 3;
          }

          return SizedBox(
            width: itemSize,
            height: itemSize,
            child:
                MemoryCard(
                      memory: memories[index],
                      index: index,
                      isSelected: ref
                          .watch(timelineProvider)
                          .selectedIds
                          .contains(memories[index].id),
                      isSelectionMode: ref
                          .watch(timelineProvider)
                          .isSelectionMode,
                      onTap: () {
                        final tl = ref.read(timelineProvider);
                        if (tl.isSelectionMode) {
                          ref
                              .read(timelineProvider.notifier)
                              .toggleSelection(memories[index].id);
                        } else {
                          _openMemory(memories[index]);
                        }
                      },
                      onLongPress: () {
                        HapticFeedback.mediumImpact();
                        ref
                            .read(timelineProvider.notifier)
                            .toggleSelection(memories[index].id);
                      },
                    )
                    .animate()
                    .fadeIn(
                      duration: 350.ms,
                      delay: (40 * index).ms,
                      curve: Curves.easeOut,
                    )
                    .scale(
                      begin: const Offset(0.92, 0.92),
                      end: const Offset(1, 1),
                      duration: 350.ms,
                      delay: (40 * index).ms,
                      curve: Curves.easeOutCubic,
                    ),
          );
        }),
      ),
    );
  }

  void _openMemory(Memory memory) {
    HapticFeedback.selectionClick();
    context.push('/viewer', extra: {'memoryId': memory.id, 'initialIndex': 0});
  }

  Map<String, List<Memory>> _groupByDate(List<Memory> memories) {
    final Map<String, List<Memory>> grouped = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final memory in memories) {
      final date = DateTime(
        memory.createdAt.year,
        memory.createdAt.month,
        memory.createdAt.day,
      );

      String key;
      if (date == today) {
        key = AppStrings.today;
      } else if (date == yesterday) {
        key = AppStrings.yesterday;
      } else if (date.year == now.year) {
        key = DateFormat('MMMM d').format(date);
      } else {
        key = DateFormat('MMMM d, y').format(date);
      }

      grouped.putIfAbsent(key, () => []).add(memory);
    }

    return grouped;
  }

  Widget _buildLoadingShimmer(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width - 24;
    final itemSize = (screenWidth - 8) / 3;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Shimmer.fromColors(
        baseColor: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        highlightColor: isDark ? Colors.grey.shade700 : Colors.grey.shade50,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 50,
              height: 12,
              margin: const EdgeInsets.only(left: 4, bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: List.generate(9, (index) {
                return Container(
                  width: itemSize,
                  height: itemSize,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              error,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => ref.read(timelineProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
