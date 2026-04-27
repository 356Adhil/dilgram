import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../timeline/application/timeline_provider.dart';
import '../../timeline/domain/memory_model.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _currentMonth;
  late PageController _monthController;

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
    _monthController = PageController(initialPage: 1200); // center
  }

  @override
  void dispose() {
    _monthController.dispose();
    super.dispose();
  }

  DateTime _monthForPage(int page) {
    final diff = page - 1200;
    return DateTime(_currentMonth.year, _currentMonth.month + diff);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeline = ref.watch(timelineProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Gallery',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined, size: 22),
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.surfaceContainerHigh
                  .withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: PageView.builder(
        controller: _monthController,
        onPageChanged: (page) {
          setState(() => _currentMonth = _monthForPage(page));
        },
        itemBuilder: (context, page) {
          final month = _monthForPage(page);
          return _MonthCalendar(month: month, memories: timeline.memories);
        },
      ),
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  final DateTime month;
  final List<Memory> memories;

  const _MonthCalendar({required this.month, required this.memories});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final firstWeekday = DateTime(month.year, month.month, 1).weekday; // 1=Mon
    final offset = firstWeekday % 7; // 0=Sun style

    // Group memories by day
    final Map<int, Memory> dayMemories = {};
    for (final m in memories) {
      if (m.createdAt.year == month.year && m.createdAt.month == month.month) {
        dayMemories.putIfAbsent(m.createdAt.day, () => m);
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              DateFormat('MMMM yyyy').format(month),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ),

          // Day labels
          Row(
            children: ['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((d) {
              return Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),

          // Calendar grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: offset + daysInMonth,
            itemBuilder: (context, index) {
              if (index < offset) return const SizedBox();

              final day = index - offset + 1;
              final memory = dayMemories[day];
              final isToday =
                  DateTime.now().year == month.year &&
                  DateTime.now().month == month.month &&
                  DateTime.now().day == day;

              return _CalendarDay(day: day, memory: memory, isToday: isToday)
                  .animate()
                  .fadeIn(
                    duration: 300.ms,
                    delay: (index * 15).ms,
                    curve: Curves.easeOut,
                  )
                  .scale(
                    begin: const Offset(0.85, 0.85),
                    end: const Offset(1, 1),
                    duration: 300.ms,
                    delay: (index * 15).ms,
                    curve: Curves.easeOutCubic,
                  );
            },
          ),
        ],
      ),
    );
  }
}

class _CalendarDay extends StatelessWidget {
  final int day;
  final Memory? memory;
  final bool isToday;

  const _CalendarDay({required this.day, this.memory, this.isToday = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (memory != null && memory!.mediaItems.isNotEmpty) {
      final url = memory!.mediaItems.first.isVideo
          ? (memory!.mediaItems.first.thumbnailUrl ??
                memory!.mediaItems.first.url)
          : memory!.mediaItems.first.url;

      return GestureDetector(
        onTap: () => context.push(
          '/viewer',
          extra: {'memoryId': memory!.id, 'initialIndex': 0},
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: isToday
                ? Border.all(color: theme.colorScheme.primary, width: 2)
                : null,
          ),
          child: ClipOval(
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (_, __) =>
                  Container(color: theme.colorScheme.surfaceContainerHigh),
              errorWidget: (_, __, ___) => Container(
                color: theme.colorScheme.surfaceContainerHigh,
                child: Center(
                  child: Text(
                    '$day',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Empty day (no memory)
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isToday
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        border: isToday
            ? Border.all(color: theme.colorScheme.primary, width: 1.5)
            : null,
      ),
      child: Center(
        child: Text(
          '$day',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
            color: isToday
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withValues(alpha: 0.25),
          ),
        ),
      ),
    );
  }
}
