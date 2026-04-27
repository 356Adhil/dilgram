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

class _MediaViewerScreenState extends ConsumerState<MediaViewerScreen> {
  late PageController _pageController;
  int _currentIndex = 0;
  bool _showOverlay = true;
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final memory = _memory;
      if (memory != null && memory.mediaItems.isNotEmpty) {
        final item = memory.mediaItems[_currentIndex];
        if (item.isVideo) {
          _initVideo(item.url);
        }
      }
    });
  }

  Memory? get _memory =>
      ref.read(timelineProvider.notifier).getMemoryById(widget.memoryId);

  void _initVideo(String url) {
    _disposeVideo();
    _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(url))
      ..initialize().then((_) {
        if (mounted) {
          _chewieController = ChewieController(
            videoPlayerController: _videoPlayerController!,
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
        await ref.read(apiServiceProvider).deleteMemory(widget.memoryId);
        ref.read(timelineProvider.notifier).removeMemory(widget.memoryId);
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
      final item = memory.mediaItems[_currentIndex];
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
    final memory = _memory;
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
                              widget.memoryId,
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
    _pageController.dispose();
    _disposeVideo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final memory = _memory;
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showOverlay = !_showOverlay),
        onVerticalDragUpdate: (details) {
          setState(() => _dragOffset += details.delta.dy);
        },
        onVerticalDragEnd: (details) {
          if (_dragOffset.abs() > 100) {
            context.pop();
          } else {
            setState(() => _dragOffset = 0);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.translationValues(0, _dragOffset.clamp(0, 300), 0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Media pages
              PageView.builder(
                controller: _pageController,
                itemCount: memory.mediaItems.length,
                onPageChanged: (index) {
                  setState(() => _currentIndex = index);
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

              // Top overlay
              if (_showOverlay)
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

              // Bottom overlay — floating action bar + page indicator
              if (_showOverlay)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Description
                        if (memory.description != null &&
                            memory.description!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              memory.description!,
                              style: GoogleFonts.inter(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 14,
                                height: 1.4,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        const SizedBox(height: 12),
                        // Page indicator
                        if (memory.mediaItems.length > 1)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(memory.mediaItems.length, (
                              index,
                            ) {
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                width: index == _currentIndex ? 20 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: index == _currentIndex
                                      ? Colors.white
                                      : Colors.white38,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              );
                            }),
                          ),
                        const SizedBox(height: 16),
                        // Floating action bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _ActionButton(
                                    icon: memory.isFavorite
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    label: 'Favorite',
                                    onTap: () {
                                      ref
                                          .read(timelineProvider.notifier)
                                          .toggleFavorite(widget.memoryId);
                                      HapticFeedback.lightImpact();
                                    },
                                    color: memory.isFavorite
                                        ? Colors.redAccent
                                        : null,
                                  ),
                                  Container(
                                    width: 1,
                                    height: 24,
                                    color: Colors.white.withValues(alpha: 0.15),
                                  ),
                                  _ActionButton(
                                    icon: Icons.share_outlined,
                                    label: 'Share',
                                    onTap: () => _shareMemory(memory),
                                  ),
                                  Container(
                                    width: 1,
                                    height: 24,
                                    color: Colors.white.withValues(alpha: 0.15),
                                  ),
                                  _ActionButton(
                                    icon: Icons.edit_outlined,
                                    label: 'Edit',
                                    onTap: _showEditSheet,
                                  ),
                                  Container(
                                    width: 1,
                                    height: 24,
                                    color: Colors.white.withValues(alpha: 0.15),
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
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoView(MediaItem item) {
    return Hero(
      tag: 'memory_${widget.memoryId}',
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
      return Center(child: Chewie(controller: _chewieController!));
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (item.thumbnailUrl != null)
          CachedNetworkImage(imageUrl: item.thumbnailUrl!, fit: BoxFit.contain),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: c, size: 22),
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
