import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../services/api_service.dart';

class JournalScreen extends ConsumerStatefulWidget {
  final String? initialDate;

  const JournalScreen({super.key, this.initialDate});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  Map<String, dynamic>? _journal;
  bool _isLoading = true;
  String? _error;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    if (widget.initialDate != null) {
      _selectedDate = DateTime.parse(widget.initialDate!);
    } else {
      _selectedDate = DateTime.now();
    }
    _loadJournal();
  }

  Future<void> _loadJournal() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiServiceProvider);
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final data = await api.getJournal(date: dateStr);
      if (mounted) {
        setState(() {
          _journal = data['journal'] as Map<String, dynamic>?;
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      HapticFeedback.selectionClick();
      setState(() => _selectedDate = picked);
      _loadJournal();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'AI Journal',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_rounded, size: 20),
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(strokeWidth: 2.5),
                  const SizedBox(height: 16),
                  Text(
                    'Writing your diary...',
                    style: GoogleFonts.inter(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            )
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: theme.colorScheme.error.withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _loadJournal,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : _journal == null
          ? _buildEmptyState(theme)
          : _buildJournal(theme),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.auto_stories_outlined,
            size: 64,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No memories on ${DateFormat('MMMM d, yyyy').format(_selectedDate)}',
            style: GoogleFonts.inter(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_rounded, size: 18),
            label: const Text('Pick another date'),
          ),
        ],
      ),
    );
  }

  Widget _buildJournal(ThemeData theme) {
    final journal = _journal!;
    final title = journal['title'] as String? ?? 'A Day to Remember';
    final entry = journal['entry'] as String? ?? '';
    final mood = journal['mood'] as String? ?? '';
    final quote = journal['quote'] as String? ?? '';
    final coverPhoto = journal['coverPhoto'] as String?;
    final memoryCount = journal['memoryCount'] as int? ?? 0;
    final memories =
        (journal['memories'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
        [];
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Cover photo
        if (coverPhoto != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: CachedNetworkImage(
              imageUrl: coverPhoto,
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ).animate().fadeIn(duration: 500.ms),

        if (coverPhoto != null) const SizedBox(height: 20),

        // Date
        Text(
          dateStr,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.primary,
            letterSpacing: 0.5,
          ),
        ).animate().fadeIn(duration: 400.ms, delay: 100.ms),

        const SizedBox(height: 8),

        // Title
        Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ).animate().fadeIn(duration: 400.ms, delay: 150.ms),

        const SizedBox(height: 6),

        // Mood + count
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                mood,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$memoryCount memories',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ).animate().fadeIn(duration: 400.ms, delay: 200.ms),

        const SizedBox(height: 24),

        // Journal entry
        Text(
          entry,
          style: GoogleFonts.inter(
            fontSize: 16,
            height: 1.8,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
          ),
        ).animate().fadeIn(duration: 500.ms, delay: 300.ms),

        // Quote
        if (quote.isNotEmpty) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: theme.colorScheme.primary.withValues(alpha: 0.4),
                  width: 3,
                ),
              ),
            ),
            child: Text(
              '"$quote"',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                height: 1.5,
              ),
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 400.ms),
        ],

        // Linked memories
        if (memories.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            "Today's Moments",
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: memories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final m = memories[index];
                final thumb = m['thumbnail'] as String?;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.push(
                      '/viewer',
                      extra: {
                        'memoryId': m['id'].toString(),
                        'initialIndex': 0,
                      },
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: thumb != null
                        ? CachedNetworkImage(
                            imageUrl: thumb,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 80,
                            height: 80,
                            color: theme.colorScheme.surfaceContainerHigh,
                            child: const Icon(Icons.image_outlined),
                          ),
                  ),
                ).animate().fadeIn(
                  duration: 300.ms,
                  delay: (450 + index * 50).ms,
                );
              },
            ),
          ),
        ],

        const SizedBox(height: 32),
      ],
    );
  }
}
