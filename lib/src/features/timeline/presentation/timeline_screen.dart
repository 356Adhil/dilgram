import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
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
          SliverAppBar(
            floating: true,
            snap: true,
            title: Text(
              AppStrings.appName,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
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
                ),
              ),
              IconButton(
                onPressed: () => context.push('/settings'),
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
        ],
        body: RefreshIndicator(
          onRefresh: () => ref.read(timelineProvider.notifier).refresh(),
          child: _buildBody(timeline, theme),
        ),
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
      padding: const EdgeInsets.only(top: 8, bottom: 100),
      itemCount: entries.length + (timeline.isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= entries.length) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.75,
        ),
        itemCount: memories.length,
        itemBuilder: (context, index) {
          return MemoryCard(
            memory: memories[index],
            onTap: () => _openMemory(memories[index]),
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
        baseColor: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
        highlightColor: isDark ? Colors.grey.shade700 : Colors.grey.shade100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 80,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.75,
              ),
              itemCount: 6,
              itemBuilder: (context, index) {
                return Container(
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
    return FloatingActionButton.extended(
      onPressed: () => _showAddOptions(context),
      icon: const Icon(Icons.add_a_photo_outlined),
      label: const Text('Capture'),
      elevation: 4,
    );
  }

  void _showAddOptions(BuildContext context) {
    final theme = Theme.of(context);
    HapticFeedback.mediumImpact();

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
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
