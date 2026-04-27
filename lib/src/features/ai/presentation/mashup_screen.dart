import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../services/api_service.dart';

class MashupScreen extends ConsumerStatefulWidget {
  const MashupScreen({super.key});

  @override
  ConsumerState<MashupScreen> createState() => _MashupScreenState();
}

class _MashupScreenState extends ConsumerState<MashupScreen> {
  String? _person;
  String? _place;
  String? _vibe;
  Map<String, dynamic>? _result;
  bool _isLoading = false;
  String? _error;

  final _personController = TextEditingController();
  final _placeController = TextEditingController();
  final _vibeController = TextEditingController();

  @override
  void dispose() {
    _personController.dispose();
    _placeController.dispose();
    _vibeController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    _person = _personController.text.trim().isNotEmpty
        ? _personController.text.trim()
        : null;
    _place = _placeController.text.trim().isNotEmpty
        ? _placeController.text.trim()
        : null;
    _vibe = _vibeController.text.trim().isNotEmpty
        ? _vibeController.text.trim()
        : null;

    if (_person == null && _place == null && _vibe == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one filter')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });

    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.getMashup(
        person: _person,
        place: _place,
        vibe: _vibe,
      );
      if (mounted) {
        setState(() {
          _result = data['mashup'] as Map<String, dynamic>?;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        String msg = 'Something went wrong. Try again.';
        if (e is DioException) {
          if (e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.receiveTimeout) {
            msg = 'Request timed out. The AI is taking too long.';
          } else if (e.type == DioExceptionType.connectionError) {
            msg = 'Cannot connect to server. Check your internet.';
          } else if (e.response?.data is Map) {
            msg = e.response?.data['error'] ?? msg;
          }
        }
        setState(() {
          _error = msg;
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
        title: Text(
          'AI Mashup',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Header
          Text(
            'Create a story from your memories',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ).animate().fadeIn(duration: 300.ms),
          const SizedBox(height: 4),
          Text(
            'Filter by person, place, or vibe to generate a unique narrative',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ).animate().fadeIn(duration: 300.ms, delay: 50.ms),
          const SizedBox(height: 24),

          // Filters
          _buildField(
            theme,
            controller: _personController,
            icon: Icons.person_outline_rounded,
            hint: 'Person (e.g. man in blue shirt)',
          ),
          const SizedBox(height: 12),
          _buildField(
            theme,
            controller: _placeController,
            icon: Icons.place_outlined,
            hint: 'Place (e.g. beach, home)',
          ),
          const SizedBox(height: 12),
          _buildField(
            theme,
            controller: _vibeController,
            icon: Icons.auto_awesome_outlined,
            hint: 'Vibe (e.g. golden hour, cozy)',
          ),

          const SizedBox(height: 20),

          // Generate button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _isLoading ? null : _generate,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome_rounded, size: 20),
              label: Text(
                _isLoading ? 'Creating story...' : 'Generate Story',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: GoogleFonts.inter(
                color: theme.colorScheme.error,
                fontSize: 13,
              ),
            ),
          ],

          // Result
          if (_result != null) ...[
            const SizedBox(height: 28),
            _buildResult(theme),
          ],
        ],
      ),
    );
  }

  Widget _buildField(
    ThemeData theme, {
    required TextEditingController controller,
    required IconData icon,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      style: GoogleFonts.inter(fontSize: 15),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, size: 20),
        hintText: hint,
        hintStyle: GoogleFonts.inter(
          fontSize: 14,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
        ),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHigh.withValues(
          alpha: 0.5,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }

  Widget _buildResult(ThemeData theme) {
    final result = _result!;
    final title = result['title'] as String? ?? 'Your Story';
    final story = result['story'] as String? ?? '';
    final themeName = result['theme'] as String? ?? '';
    final highlights = (result['highlights'] as List<dynamic>?) ?? [];
    final coverPhotos = (result['coverPhotos'] as List<dynamic>?) ?? [];
    final memoryCount = result['memoryCount'] as int? ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cover photos
        if (coverPhotos.isNotEmpty)
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: coverPhotos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CachedNetworkImage(
                    imageUrl: coverPhotos[index] as String,
                    width: 130,
                    height: 160,
                    fit: BoxFit.cover,
                  ),
                ).animate().fadeIn(duration: 400.ms, delay: (index * 80).ms);
              },
            ),
          ),

        if (coverPhotos.isNotEmpty) const SizedBox(height: 20),

        // Theme badge
        if (themeName.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              themeName,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ).animate().fadeIn(duration: 300.ms),

        const SizedBox(height: 10),

        // Title
        Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ).animate().fadeIn(duration: 400.ms, delay: 100.ms),

        const SizedBox(height: 4),
        Text(
          '$memoryCount memories woven together',
          style: GoogleFonts.inter(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ).animate().fadeIn(duration: 300.ms, delay: 150.ms),

        const SizedBox(height: 16),

        // Story
        Text(
          story,
          style: GoogleFonts.inter(
            fontSize: 16,
            height: 1.8,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
          ),
        ).animate().fadeIn(duration: 500.ms, delay: 200.ms),

        // Highlights
        if (highlights.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Highlights',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 10),
          ...highlights.asMap().entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '✦',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.value as String,
                      style: GoogleFonts.inter(fontSize: 14, height: 1.5),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(
              duration: 300.ms,
              delay: (300 + entry.key * 50).ms,
            );
          }),
        ],

        const SizedBox(height: 32),
      ],
    );
  }
}
