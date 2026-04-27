import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../domain/memory_model.dart';

class MemoryCard extends StatelessWidget {
  final Memory memory;
  final VoidCallback onTap;
  final int index;

  const MemoryCard({
    super.key,
    required this.memory,
    required this.onTap,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaItem = memory.mediaItems.isNotEmpty
        ? memory.mediaItems.first
        : null;

    return GestureDetector(
      onTap: onTap,
      child: Hero(
        tag: 'memory_${memory.id}',
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: theme.colorScheme.surfaceContainerHigh,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (mediaItem != null)
                  _buildThumbnail(mediaItem, theme)
                else
                  _buildPlaceholder(theme),

                // Video indicator
                if (mediaItem != null && mediaItem.isVideo)
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 10,
                          ),
                          if (mediaItem.duration != null) ...[
                            const SizedBox(width: 1),
                            Text(
                              mediaItem.formattedDuration,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                // Multi-media count
                if (memory.mediaItems.length > 1)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.photo_library_rounded,
                            color: Colors.white,
                            size: 10,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${memory.mediaItems.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(MediaItem mediaItem, ThemeData theme) {
    final imageUrl = mediaItem.isVideo
        ? (mediaItem.thumbnailUrl ?? mediaItem.url)
        : mediaItem.url;

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        color: theme.colorScheme.surfaceContainerHigh,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: theme.colorScheme.surfaceContainerHigh,
        child: Icon(
          Icons.broken_image_outlined,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
          size: 22,
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Icon(
        Icons.image_outlined,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
        size: 24,
      ),
    );
  }
}
