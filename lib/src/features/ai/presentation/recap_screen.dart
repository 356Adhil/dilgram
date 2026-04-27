import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../timeline/domain/memory_model.dart';
import '../../../services/api_service.dart';

class RecapScreen extends ConsumerStatefulWidget {
  final String period; // 'weekly' or 'monthly'

  const RecapScreen({super.key, required this.period});

  @override
  ConsumerState<RecapScreen> createState() => _RecapScreenState();
}

class _RecapScreenState extends ConsumerState<RecapScreen> {
  Map<String, dynamic>? _recap;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRecap();
  }

  Future<void> _loadRecap() async {
    try {
      final api = ref.read(apiServiceProvider);
      final data = widget.period == 'weekly'
          ? await api.getWeeklyRecap()
          : await api.getMonthlyRecap();
      if (mounted) {
        setState(() {
          _recap = data['recap'] as Map<String, dynamic>?;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : _error != null
          ? _buildError(theme)
          : _recap == null
          ? _buildEmpty(theme)
          : _buildRecap(theme),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: theme.colorScheme.error.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text('Failed to load recap', style: theme.textTheme.bodyLarge),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => context.pop(),
            child: const Text('Go Back'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_album_outlined,
            size: 64,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No memories this ${widget.period == "weekly" ? "week" : "month"} yet',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => context.pop(),
            child: const Text('Go Back'),
          ),
        ],
      ),
    );
  }

  Widget _buildRecap(ThemeData theme) {
    final ai = _recap!['ai'] as Map<String, dynamic>?;
    final coverPhoto = _recap!['coverPhoto'] as String?;
    final memoryCount = _recap!['memoryCount'] as int? ?? 0;
    final photoCount = _recap!['photoCount'] as int? ?? 0;
    final locations =
        (_recap!['locations'] as List<dynamic>?)?.cast<String>() ?? [];
    final moods = (_recap!['moods'] as List<dynamic>?)?.cast<String>() ?? [];
    final dateRange = _recap!['dateRange'] as Map<String, dynamic>?;
    final memories =
        (_recap!['memories'] as List<dynamic>?)
            ?.map((e) => Memory.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    String dateRangeStr = '';
    if (dateRange != null) {
      final start = DateTime.parse(dateRange['start'] as String);
      final end = DateTime.parse(dateRange['end'] as String);
      dateRangeStr =
          '${DateFormat('MMM d').format(start)} — ${DateFormat('MMM d, y').format(end)}';
    }

    return CustomScrollView(
      slivers: [
        // Cover hero
        SliverAppBar(
          expandedHeight: 300,
          pinned: true,
          leading: IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black38,
              foregroundColor: Colors.white,
            ),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: coverPhoto != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: coverPhoto,
                        fit: BoxFit.cover,
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.7),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 16,
                        left: 16,
                        right: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ai?['theme'] ??
                                  (widget.period == 'weekly'
                                      ? 'Your Week'
                                      : 'Your Month'),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              dateRangeStr,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Container(
                    color: theme.colorScheme.primaryContainer,
                    child: Center(
                      child: Icon(
                        Icons.auto_awesome,
                        size: 64,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
          ),
        ),

        // Stats bar
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _RecapStat(
                  value: '$memoryCount',
                  label: 'Memories',
                  icon: Icons.collections_outlined,
                ),
                _RecapStat(
                  value: '$photoCount',
                  label: 'Photos',
                  icon: Icons.photo_outlined,
                ),
                _RecapStat(
                  value: '${locations.length}',
                  label: 'Places',
                  icon: Icons.place_outlined,
                ),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
        ),

        // AI Story
        if (ai != null && ai['story'] != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.auto_stories,
                          color: theme.colorScheme.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'AI Story',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      ai['story'] as String,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        height: 1.6,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.85,
                        ),
                      ),
                    ),
                    if (ai['highlights'] != null &&
                        (ai['highlights'] as List).isNotEmpty) ...[
                      const SizedBox(height: 16),
                      ...((ai['highlights'] as List).map(
                        (h) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '✦ ',
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontSize: 14,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  h as String,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )),
                    ],
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 300.ms),
            ),
          ),

        // Locations
        if (locations.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Places Visited',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: locations
                        .map(
                          (loc) => Chip(
                            avatar: const Icon(Icons.place, size: 16),
                            label: Text(
                              loc,
                              style: GoogleFonts.inter(fontSize: 12),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                        .toList(),
                  ),
                ],
              ).animate().fadeIn(duration: 400.ms, delay: 400.ms),
            ),
          ),

        // Moods
        if (moods.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Moods',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: moods
                        .map(
                          (mood) => Chip(
                            label: Text(
                              mood,
                              style: GoogleFonts.inter(fontSize: 12),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                        .toList(),
                  ),
                ],
              ).animate().fadeIn(duration: 400.ms, delay: 500.ms),
            ),
          ),

        // Memory grid
        if (memories.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Memories',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

        if (memories.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final memory = memories[index];
                final item = memory.mediaItems.isNotEmpty
                    ? memory.mediaItems.first
                    : null;
                final url = item != null
                    ? (item.isVideo
                          ? (item.thumbnailUrl ?? item.url)
                          : item.url)
                    : null;

                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.push(
                      '/viewer',
                      extra: {'memoryId': memory.id, 'initialIndex': 0},
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: url != null
                        ? CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: theme.colorScheme.surfaceContainerHigh,
                            ),
                          )
                        : Container(
                            color: theme.colorScheme.surfaceContainerHigh,
                            child: const Icon(Icons.image_outlined),
                          ),
                  ),
                ).animate().fadeIn(duration: 300.ms, delay: (50 * index).ms);
              }, childCount: memories.length),
            ),
          ),
      ],
    );
  }
}

class _RecapStat extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;

  const _RecapStat({
    required this.value,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}
