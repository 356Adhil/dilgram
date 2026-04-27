import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../domain/memory_model.dart';

class MemoryCard extends StatelessWidget {
  final Memory memory;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final int index;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isLarge;

  const MemoryCard({
    super.key,
    required this.memory,
    required this.onTap,
    this.onLongPress,
    this.index = 0,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.isLarge = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaItem = memory.mediaItems.isNotEmpty
        ? memory.mediaItems.first
        : null;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Hero(
        tag: 'memory_${memory.id}',
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: theme.colorScheme.surfaceContainerHigh,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (mediaItem != null)
                  _buildThumbnail(mediaItem, theme)
                else
                  _buildPlaceholder(theme),

                // Subtle bottom gradient for depth
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withValues(alpha: isLarge ? 0.45 : 0.15),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),

                // Title overlay on large cards
                if (isLarge && memory.title != null && memory.title!.isNotEmpty)
                  Positioned(
                    bottom: 10,
                    left: 10,
                    right: 10,
                    child: Text(
                      memory.title!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),

                // Mood pill on large cards
                if (isLarge && memory.mood != null && memory.mood!.isNotEmpty)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        memory.mood!,
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),

                // Video indicator
                if (mediaItem != null && mediaItem.isVideo)
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 12,
                          ),
                          if (mediaItem.duration != null) ...[
                            const SizedBox(width: 2),
                            Text(
                              mediaItem.formattedDuration,
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 10,
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
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.photo_library_rounded,
                            color: Colors.white,
                            size: 11,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${memory.mediaItems.length}',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Favorite heart
                if (memory.isFavorite && !isSelectionMode)
                  Positioned(
                    top: isLarge ? null : 6,
                    bottom: isLarge ? 8 : null,
                    left: isLarge ? null : 6,
                    right: isLarge ? 8 : null,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.favorite,
                        color: Colors.redAccent,
                        size: 13,
                      ),
                    ),
                  ),

                // Selection checkbox overlay
                if (isSelectionMode)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : Colors.black.withValues(alpha: 0.35),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.85),
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 14,
                            )
                          : null,
                    ),
                  ),

                // Dim overlay when in selection mode but not selected
                if (isSelectionMode && !isSelected)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(16),
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
            width: 18,
            height: 18,
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
