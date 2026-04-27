import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../application/timeline_provider.dart';
import '../domain/memory_model.dart';
import '../../settings/application/theme_provider.dart';
import '../../../constants/app_strings.dart';
import 'widgets/memory_card.dart';
import 'widgets/empty_state_widget.dart';
import 'widgets/timeline_date_header.dart';

class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  final _scrollController = ScrollController();
  bool _showScrollToTop = false;

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
    final show = _scrollController.offset > 400;
    if (show != _showScrollToTop) {
      setState(() => _showScrollToTop = show);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeline = ref.watch(timelineProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          NestedScrollView(
            controller: _scrollController,
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverAppBar(
                floating: true,
                snap: true,
                backgroundColor: theme.scaffoldBackgroundColor.withValues(
                  alpha: 0.85,
                ),
                surfaceTintColor: Colors.transparent,
                flexibleSpace: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(color: Colors.transparent),
                  ),
                ),
                title: Text(AppStrings.appName),
                actions: [
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
              ),
            ],
            body: RefreshIndicator(
              onRefresh: () => ref.read(timelineProvider.notifier).refresh(),
              color: theme.colorScheme.primary,
              child: _buildBody(timeline, theme),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFAB(context, theme),
    );
  }

  Widget _buildBody(TimelineState timeline, ThemeData theme) {
    if (timeline.isLoading && timeline.memories.isEmpty) {
      return _buildLoadingShimmer(theme);
    }

    if (timeline.error != null && timeline.memories.isEmpty) {
      return _buildErrorState(theme, timeline.error!);
    }

    if (timeline.memories.isEmpty) {
      return const EmptyStateWidget();
    }

    return _buildTimeline(timeline, theme);
  }

  Widget _buildTimeline(TimelineState timeline, ThemeData theme) {
    final grouped = _groupByDate(timeline.memories);
    final entries = grouped.entries.toList();

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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TimelineDateHeader(date: entry.key),
            _buildMemoryGrid(entry.value, theme),
          ],
        );
      },
    );
  }

  Widget _buildMemoryGrid(List<Memory> memories, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: MasonryGridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        itemCount: memories.length,
        itemBuilder: (context, index) {
          return MemoryCard(
                memory: memories[index],
                index: index,
                onTap: () => _openMemory(memories[index]),
              )
              .animate()
              .fadeIn(
                duration: 400.ms,
                delay: (60 * index).ms,
                curve: Curves.easeOut,
              )
              .slideY(
                begin: 0.05,
                end: 0,
                duration: 400.ms,
                delay: (60 * index).ms,
                curve: Curves.easeOut,
              );
        },
      ),
    );
  }

  void _openMemory(Memory memory) {
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Shimmer.fromColors(
        baseColor: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        highlightColor: isDark ? Colors.grey.shade700 : Colors.grey.shade50,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 70,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 16),
            MasonryGridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              itemCount: 6,
              itemBuilder: (context, index) {
                final heights = [200.0, 260.0, 180.0, 240.0, 220.0, 190.0];
                return Container(
                  height: heights[index],
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                );
              },
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

  Widget _buildFAB(BuildContext context, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_showScrollToTop)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FloatingActionButton.small(
              heroTag: 'scroll_top',
              onPressed: () {
                _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                );
              },
              backgroundColor: theme.colorScheme.surfaceContainerHigh,
              elevation: 0,
              child: Icon(
                Icons.arrow_upward_rounded,
                color: theme.colorScheme.onSurface,
                size: 20,
              ),
            ),
          ),
        FloatingActionButton(
          onPressed: () => _showAddOptions(context),
          child: const Icon(Icons.add_rounded, size: 28),
        ),
      ],
    );
  }

  void _showAddOptions(BuildContext context) {
    final theme = Theme.of(context);
    HapticFeedback.mediumImpact();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text('Add Memory', style: theme.textTheme.titleLarge),
              const SizedBox(height: 20),
              _OptionTile(
                icon: Icons.camera_alt_outlined,
                title: AppStrings.takePhoto,
                subtitle: 'Capture a photo with your camera',
                onTap: () {
                  Navigator.pop(context);
                  context.push('/camera', extra: {'mode': 'photo'});
                },
              ),
              const SizedBox(height: 8),
              _OptionTile(
                icon: Icons.videocam_outlined,
                title: AppStrings.recordVideo,
                subtitle: 'Record a video moment',
                onTap: () {
                  Navigator.pop(context);
                  context.push('/camera', extra: {'mode': 'video'});
                },
              ),
              const SizedBox(height: 8),
              _OptionTile(
                icon: Icons.photo_library_outlined,
                title: AppStrings.uploadFromGallery,
                subtitle: 'Choose from your photo library',
                onTap: () {
                  Navigator.pop(context);
                  _pickFromGallery();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final files = await picker.pickMultipleMedia();

    if (files.isNotEmpty && mounted) {
      // For single file, go to preview
      if (files.length == 1) {
        final file = files.first;
        final isVideo =
            file.mimeType?.startsWith('video') == true ||
            file.path.endsWith('.mp4') ||
            file.path.endsWith('.mov');
        context.push(
          '/preview',
          extra: {'filePath': file.path, 'isVideo': isVideo},
        );
      } else {
        // For multiple files, go to preview with the first one
        final file = files.first;
        final isVideo =
            file.mimeType?.startsWith('video') == true ||
            file.path.endsWith('.mp4') ||
            file.path.endsWith('.mov');
        context.push(
          '/preview',
          extra: {'filePath': file.path, 'isVideo': isVideo},
        );
      }
    }
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
