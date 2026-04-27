import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../timeline/domain/memory_model.dart';
import '../../../services/api_service.dart';

class PersonMemoriesScreen extends ConsumerStatefulWidget {
  final String label;

  const PersonMemoriesScreen({super.key, required this.label});

  @override
  ConsumerState<PersonMemoriesScreen> createState() =>
      _PersonMemoriesScreenState();
}

class _PersonMemoriesScreenState extends ConsumerState<PersonMemoriesScreen> {
  List<Memory>? _memories;
  String? _thumbnail;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.getGroupedMemories(by: 'people');
      final people = (data['people'] as List<dynamic>?) ?? [];
      final match = people.firstWhere(
        (p) => (p as Map<String, dynamic>)['label'] == widget.label,
        orElse: () => null,
      );
      if (match != null && mounted) {
        final matchMap = match as Map<String, dynamic>;
        final memoryList = (matchMap['memories'] as List<dynamic>)
            .map((e) => Memory.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() {
          _memories = memoryList;
          _thumbnail = matchMap['thumbnail'] as String?;
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() {
          _memories = [];
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
      appBar: AppBar(
        title: Row(
          children: [
            if (_thumbnail != null)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.2),
                      width: 1.5,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CachedNetworkImage(
                    imageUrl: _thumbnail!,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Icon(
                      Icons.person,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Text(
                widget.label,
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        centerTitle: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: theme.colorScheme.error.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text('Failed to load', style: theme.textTheme.bodyLarge),
                ],
              ),
            )
          : _memories == null || _memories!.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 64,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No memories found',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
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
