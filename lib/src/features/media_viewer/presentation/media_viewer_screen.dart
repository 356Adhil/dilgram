import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../../timeline/application/timeline_provider.dart';
import '../../timeline/domain/memory_model.dart';
import '../../../services/api_service.dart';
import '../../../constants/app_strings.dart';

class MediaViewerScreen extends ConsumerStatefulWidget {
  final String memoryId;
  final int initialIndex;

  const MediaViewerScreen({
    super.key,
    required this.memoryId,
    this.initialIndex = 0,
  });

  @override
  ConsumerState<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends ConsumerState<MediaViewerScreen>
    with SingleTickerProviderStateMixin {
  late PageController _mediaPageController;
  late PageController _memoryPageController;
  late ScrollController _scrollController;
  int _currentMediaIndex = 0;
  int _currentMemoryIndex = 0;
  bool _showOverlay = true;
  bool _showDetails = false;
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;

  List<Memory> _allMemories = [];

  @override
  void initState() {
    super.initState();
    _currentMediaIndex = widget.initialIndex;

    // Get all memories from timeline and find the starting index
    final timelineState = ref.read(timelineProvider);
    _allMemories = timelineState.memories;
    _currentMemoryIndex = _allMemories.indexWhere(
      (m) => m.id == widget.memoryId,
    );
    if (_currentMemoryIndex < 0) _currentMemoryIndex = 0;

    _memoryPageController = PageController(initialPage: _currentMemoryIndex);
    _mediaPageController = PageController(initialPage: widget.initialIndex);
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final memory = _currentMemory;
      if (memory != null && memory.mediaItems.isNotEmpty) {
        final idx = _currentMediaIndex.clamp(0, memory.mediaItems.length - 1);
        final item = memory.mediaItems[idx];
        if (item.isVideo) {
          _initVideo(item.url);
        }
      }
    });
  }

  Memory? get _currentMemory {
    if (_allMemories.isEmpty) return null;
    if (_currentMemoryIndex < 0 || _currentMemoryIndex >= _allMemories.length)
      return null;
    // Re-fetch from provider to get latest state (e.g. after favorite toggle)
    return ref
        .read(timelineProvider.notifier)
        .getMemoryById(_allMemories[_currentMemoryIndex].id);
  }

  String get _currentMemoryId {
    if (_allMemories.isEmpty ||
        _currentMemoryIndex < 0 ||
        _currentMemoryIndex >= _allMemories.length) {
      return widget.memoryId;
    }
    return _allMemories[_currentMemoryIndex].id;
  }

  void _onMemoryPageChanged(int index) {
    _disposeVideo();
    setState(() {
      _currentMemoryIndex = index;
      _currentMediaIndex = 0;
      _showDetails = false;
      _showOverlay = true;
    });

    // Reset scroll position
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

    // Reset media page controller
    _mediaPageController.dispose();
    _mediaPageController = PageController(initialPage: 0);

    // Init video if first item is video
    final memory = _currentMemory;
    if (memory != null && memory.mediaItems.isNotEmpty) {
      final item = memory.mediaItems[0];
      if (item.isVideo) {
        _initVideo(item.url);
      }
    }
  }

  void _initVideo(String url) {
    _disposeVideo();
    _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(url))
      ..initialize().then((_) {
        if (mounted) {
          _chewieController = ChewieController(
            videoPlayerController: _videoPlayerController!,
            aspectRatio: _videoPlayerController!.value.aspectRatio,
            autoPlay: true,
            looping: false,
            showControls: true,
            materialProgressColors: ChewieProgressColors(
              playedColor: Theme.of(context).colorScheme.primary,
              handleColor: Theme.of(context).colorScheme.primary,
              backgroundColor: Colors.white24,
              bufferedColor: Colors.white38,
            ),
          );
          setState(() {});
        }
      });
  }

  void _disposeVideo() {
    _chewieController?.dispose();
    _chewieController = null;
    _videoPlayerController?.dispose();
    _videoPlayerController = null;
  }

  Future<void> _deleteMemory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Memory'),
        content: const Text(AppStrings.deleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text(AppStrings.delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(apiServiceProvider).deleteMemory(_currentMemoryId);
        ref.read(timelineProvider.notifier).removeMemory(_currentMemoryId);
        if (mounted) {
          HapticFeedback.mediumImpact();
          context.pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete memory')),
          );
        }
      }
    }
  }

  Future<void> _shareMemory(Memory memory) async {
    try {
      final item = memory.mediaItems[_currentMediaIndex];
      final response = await http.get(Uri.parse(item.url));
      final tempDir = await getTemporaryDirectory();
      final ext = item.isVideo ? 'mp4' : 'jpg';
      final file = File('${tempDir.path}/share_memory.$ext');
      await file.writeAsBytes(response.bodyBytes);

      final text = memory.title ?? 'Check out this memory!';
      await SharePlus.instance.share(
        ShareParams(text: text, files: [XFile(file.path)]),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to share')));
      }
    }
  }

  void _showEditSheet() {
    final memory = _currentMemory;
    if (memory == null) return;

    final titleCtrl = TextEditingController(text: memory.title ?? '');
    final descCtrl = TextEditingController(text: memory.description ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Edit Memory', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 20),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Title (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Description (optional)',
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () async {
                      try {
                        await ref
                            .read(apiServiceProvider)
                            .updateMemory(
                              _currentMemoryId,
                              title: titleCtrl.text.isEmpty
                                  ? null
                                  : titleCtrl.text,
                              description: descCtrl.text.isEmpty
                                  ? null
                                  : descCtrl.text,
                            );
                        final updated = memory.copyWith(
                          title: titleCtrl.text.isEmpty ? null : titleCtrl.text,
                          description: descCtrl.text.isEmpty
                              ? null
                              : descCtrl.text,
                        );
                        ref
                            .read(timelineProvider.notifier)
                            .updateMemory(updated);
                        if (context.mounted) {
                          Navigator.pop(context);
                          setState(() {});
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Failed to update')),
                          );
                        }
                      }
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Save Changes'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _mediaPageController.dispose();
    _memoryPageController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _disposeVideo();
    super.dispose();
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    final screenH = MediaQuery.of(context).size.height;
    final threshold = screenH * 0.15;
    if (offset > threshold && !_showDetails) {
      setState(() {
        _showDetails = true;
        _showOverlay = false;
      });
    } else if (offset <= 10 && _showDetails) {
      setState(() {
        _showDetails = false;
        _showOverlay = true;
      });
    }
  }

  void _scrollToDetails() {
    final screenH = MediaQuery.of(context).size.height;
    _scrollController.animateTo(
      screenH * 0.45,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollBackToImage() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Refresh memory list from provider
    _allMemories = ref.watch(timelineProvider).memories;
    final memory = _currentMemory;
    if (memory == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'Memory not found',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final screenH = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: _showDetails ? theme.colorScheme.surface : Colors.black,
      body: PageView.builder(
        controller: _memoryPageController,
        itemCount: _allMemories.length,
        physics: _showDetails
            ? const NeverScrollableScrollPhysics()
            : const BouncingScrollPhysics(),
        onPageChanged: _onMemoryPageChanged,
        itemBuilder: (context, memoryIdx) {
          // Only build content for current and adjacent pages
          final pageMemory = ref
              .read(timelineProvider.notifier)
              .getMemoryById(_allMemories[memoryIdx].id);
          if (pageMemory == null) {
            return const Center(
              child: Text(
                'Memory not found',
                style: TextStyle(color: Colors.white54),
              ),
            );
          }
          // Only the current page gets the full interactive content
          if (memoryIdx != _currentMemoryIndex) {
            return _buildStaticPage(pageMemory);
          }
          return _buildMemoryPage(memory, theme, screenH);
        },
      ),
    );
  }

  /// Lightweight page for non-current memories (shown during swipe)
  Widget _buildStaticPage(Memory memory) {
    final item = memory.mediaItems.isNotEmpty ? memory.mediaItems[0] : null;
    if (item == null) {
      return const Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Colors.white38,
          size: 48,
        ),
      );
    }
    if (item.isVideo) {
      return Container(
        color: Colors.black,
        child: Center(
          child: item.thumbnailUrl != null
              ? CachedNetworkImage(
                  imageUrl: item.thumbnailUrl!,
                  fit: BoxFit.contain,
                )
              : const Icon(
                  Icons.videocam_rounded,
                  color: Colors.white24,
                  size: 64,
                ),
        ),
      );
    }
    return Container(
      color: Colors.black,
      child: Center(
        child: CachedNetworkImage(imageUrl: item.url, fit: BoxFit.contain),
      ),
    );
  }

  /// Full interactive page for the currently active memory
  Widget _buildMemoryPage(Memory memory, ThemeData theme, double screenH) {
    return Stack(
      children: [
        // Main scrollable content
        CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Image/video area
            SliverToBoxAdapter(
              child: GestureDetector(
                onTap: () {
                  if (_showDetails) {
                    _scrollBackToImage();
                  } else {
                    setState(() => _showOverlay = !_showOverlay);
                  }
                },
                child: Container(
                  height: screenH,
                  color: Colors.black,
                  child: PageView.builder(
                    controller: _mediaPageController,
                    itemCount: memory.mediaItems.length,
                    onPageChanged: (index) {
                      setState(() => _currentMediaIndex = index);
                      final item = memory.mediaItems[index];
                      if (item.isVideo) {
                        _initVideo(item.url);
                      } else {
                        _disposeVideo();
                      }
                    },
                    itemBuilder: (context, index) {
                      final item = memory.mediaItems[index];
                      if (item.isVideo) {
                        return _buildVideoView(item);
                      }
                      return _buildPhotoView(item);
                    },
                  ),
                ),
              ),
            ),

            // Swipe-up hint
            SliverToBoxAdapter(
              child: Container(
                color: theme.colorScheme.surface,
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.12,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),

            // Details content
            SliverToBoxAdapter(child: _buildDetailsContent(memory, theme)),
          ],
        ),

        // Top overlay (back button + title)
        if (_showOverlay && !_showDetails)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.5),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => context.pop(),
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              color: Colors.white,
                            ),
                          ),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (memory.title != null &&
                                    memory.title!.isNotEmpty)
                                  Text(
                                    memory.title!,
                                    style: GoogleFonts.plusJakartaSans(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                Text(
                                  DateFormat(
                                    'MMM d, y · h:mm a',
                                  ).format(memory.createdAt),
                                  style: GoogleFonts.inter(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Details mode top bar
        if (_showDetails)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: theme.colorScheme.surface,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _scrollBackToImage,
                        icon: Icon(
                          Icons.arrow_back_rounded,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Details',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Bottom overlay — floating action bar + page indicator
        if (_showOverlay && !_showDetails)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Swipe up hint
                  GestureDetector(
                    onTap: () => _scrollToDetails(),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.keyboard_arrow_up_rounded,
                            color: Colors.white54,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Swipe up for details',
                            style: GoogleFonts.inter(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Page indicator
                  if (memory.mediaItems.length > 1)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(memory.mediaItems.length, (
                        index,
                      ) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: index == _currentMediaIndex ? 20 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: index == _currentMediaIndex
                                ? Colors.white
                                : Colors.white38,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }),
                    ),
                  const SizedBox(height: 12),
                  // Floating action bar
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _ActionButton(
                                icon: memory.isFavorite
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                label: 'Favorite',
                                onTap: () {
                                  ref
                                      .read(timelineProvider.notifier)
                                      .toggleFavorite(_currentMemoryId);
                                  HapticFeedback.lightImpact();
                                },
                                color: memory.isFavorite
                                    ? Colors.redAccent
                                    : null,
                              ),
                              _ActionButton(
                                icon: Icons.share_outlined,
                                label: 'Share',
                                onTap: () => _shareMemory(memory),
                              ),
                              _ActionButton(
                                icon: Icons.info_outline_rounded,
                                label: 'Details',
                                onTap: () => _scrollToDetails(),
                              ),
                              _ActionButton(
                                icon: Icons.edit_outlined,
                                label: 'Edit',
                                onTap: _showEditSheet,
                              ),
                              _ActionButton(
                                icon: Icons.delete_outline_rounded,
                                label: 'Delete',
                                onTap: _deleteMemory,
                                isDestructive: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDetailsContent(Memory memory, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          if (memory.title != null && memory.title!.isNotEmpty)
            Text(
              memory.title!,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
                letterSpacing: -0.5,
                height: 1.2,
              ),
            ),

          // Date & time
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 20),
            child: Text(
              DateFormat('EEEE, MMMM d, y · h:mm a').format(memory.createdAt),
              style: GoogleFonts.inter(
                fontSize: 13,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                letterSpacing: 0.1,
              ),
            ),
          ),

          // Description in a subtle card
          if (memory.description != null && memory.description!.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.black.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                ),
              ),
              child: Text(
                memory.description!,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  height: 1.7,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Location + Mood chips
          if (memory.location?.name != null ||
              (memory.mood != null && memory.mood!.isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (memory.location?.name != null)
                    _InfoChip(
                      icon: Icons.place_outlined,
                      label: memory.location!.name!,
                      theme: theme,
                    ),
                  if (memory.mood != null && memory.mood!.isNotEmpty)
                    _InfoChip(
                      icon: Icons.mood_rounded,
                      label: memory.mood!,
                      theme: theme,
                      isPrimary: true,
                    ),
                ],
              ),
            ),

          // Tags
          if (memory.tags.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: memory.tags.map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '#$tag',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.primary.withValues(alpha: 0.7),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
          ],

          // People
          if (memory.people.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'PEOPLE',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.black.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                ),
              ),
              child: Column(
                children: memory.people.asMap().entries.map((entry) {
                  final person = entry.value;
                  final isLast = entry.key == memory.people.length - 1;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    theme.colorScheme.primary.withValues(
                                      alpha: 0.15,
                                    ),
                                    theme.colorScheme.tertiary.withValues(
                                      alpha: 0.15,
                                    ),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  person.label.isNotEmpty
                                      ? person.label[0].toUpperCase()
                                      : '?',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    person.label,
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  if (person.description != null)
                                    Text(
                                      person.description!,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.4),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isLast)
                        Divider(
                          height: 1,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.06,
                          ),
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Media info footer
          if (memory.mediaItems.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.black.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.photo_camera_outlined,
                      size: 16,
                      color: theme.colorScheme.primary.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _buildMediaSummary(memory),
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                        if (memory.mediaItems[_currentMediaIndex].width !=
                                null &&
                            memory.mediaItems[_currentMediaIndex].height !=
                                null)
                          Text(
                            '${memory.mediaItems[_currentMediaIndex].width} × ${memory.mediaItems[_currentMediaIndex].height}',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _buildMediaSummary(Memory memory) {
    final photos = memory.mediaItems.where((i) => i.isPhoto).length;
    final videos = memory.mediaItems.where((i) => i.isVideo).length;
    final parts = <String>[];
    if (photos > 0) parts.add('$photos photo${photos != 1 ? 's' : ''}');
    if (videos > 0) parts.add('$videos video${videos != 1 ? 's' : ''}');
    return parts.join(', ');
  }

  Widget _buildPhotoView(MediaItem item) {
    return Hero(
      tag: 'memory_$_currentMemoryId',
      child: PhotoView(
        imageProvider: CachedNetworkImageProvider(item.url),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 3,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        loadingBuilder: (context, event) {
          return const Center(
            child: CircularProgressIndicator(
              color: Colors.white38,
              strokeWidth: 2,
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return const Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: Colors.white38,
              size: 48,
            ),
          );
        },
      ),
    );
  }

  Widget _buildVideoView(MediaItem item) {
    if (_chewieController != null &&
        _videoPlayerController!.value.isInitialized) {
      final videoAspect = _videoPlayerController!.value.aspectRatio;
      return Center(
        child: AspectRatio(
          aspectRatio: videoAspect,
          child: Chewie(controller: _chewieController!),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (item.thumbnailUrl != null)
          Center(
            child: CachedNetworkImage(
              imageUrl: item.thumbnailUrl!,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        const Center(
          child: CircularProgressIndicator(
            color: Colors.white38,
            strokeWidth: 2,
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final ThemeData theme;
  final bool isPrimary;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.theme,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isPrimary
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
            : theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: isPrimary
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isPrimary
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;
  final Color? color;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? (isDestructive ? const Color(0xFFFF6B6B) : Colors.white);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: c, size: 20),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.inter(
                color: c,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
