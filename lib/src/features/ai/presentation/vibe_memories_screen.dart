import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../timeline/domain/memory_model.dart';
import '../../../services/api_service.dart';

class VibeMemoriesScreen extends ConsumerStatefulWidget {
  final String vibe;

  const VibeMemoriesScreen({super.key, required this.vibe});

  @override
  ConsumerState<VibeMemoriesScreen> createState() => _VibeMemoriesScreenState();
}

class _VibeMemoriesScreenState extends ConsumerState<VibeMemoriesScreen> {
  List<Memory>? _memories;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.getVibeMemories(widget.vibe);
      final list = (data['memories'] as List<dynamic>?) ?? [];
      if (mounted) {
        setState(() {
          _memories = list
              .map((e) => Memory.fromJson(e as Map<String, dynamic>))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '✨ ${widget.vibe}',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : _memories == null || _memories!.isEmpty
          ? Center(
              child: Text(
                'No memories with this vibe',
                style: GoogleFonts.inter(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: _memories!.length,
              itemBuilder: (context, index) {
                final memory = _memories![index];
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
              },
            ),
    );
  }
}
