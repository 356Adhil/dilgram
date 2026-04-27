import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:go_router/go_router.dart';
import '../../../services/api_service.dart';

final moodDataProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  final cached = ref.read(cachedApiProvider);
  final data = await cached.getMoodData();
  return data ?? {};
});

class MoodTimelineScreen extends ConsumerWidget {
  const MoodTimelineScreen({super.key});

  static const Map<String, Color> moodColors = {
    'joyful': Color(0xFFFFD93D),
    'serene': Color(0xFF6EC6FF),
    'nostalgic': Color(0xFFCE93D8),
    'cozy': Color(0xFFFFAB91),
    'adventurous': Color(0xFF81C784),
    'reflective': Color(0xFF90CAF9),
    'energetic': Color(0xFFFF8A65),
    'peaceful': Color(0xFFA5D6A7),
    'romantic': Color(0xFFF48FB1),
    'melancholy': Color(0xFF78909C),
    'excited': Color(0xFFFFD54F),
    'grateful': Color(0xFFFFCC80),
    'inspired': Color(0xFFB39DDB),
    'playful': Color(0xFF4DD0E1),
    'calm': Color(0xFF80DEEA),
    'dreamy': Color(0xFFE1BEE7),
    'warm': Color(0xFFFFAB40),
    'mysterious': Color(0xFF7E57C2),
    'cheerful': Color(0xFFFFF176),
    'content': Color(0xFFC5E1A5),
  };

  static const Map<String, String> moodEmojis = {
    'joyful': '🌟',
    'serene': '🧘',
    'nostalgic': '💭',
    'cozy': '☕',
    'adventurous': '🌍',
    'reflective': '🪞',
    'energetic': '⚡',
    'peaceful': '🕊️',
    'romantic': '💕',
    'melancholy': '🌧️',
    'excited': '🎉',
    'grateful': '🙏',
    'inspired': '💡',
    'playful': '🎈',
    'calm': '🌊',
    'dreamy': '✨',
    'warm': '🔥',
    'mysterious': '🌙',
    'cheerful': '😊',
    'content': '🌿',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final moodData = ref.watch(moodDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Mood Timeline',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
      ),
      body: moodData.when(
        data: (data) => _buildContent(context, theme, data),
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ThemeData theme,
    Map<String, dynamic> data,
  ) {
    final days = (data['days'] as List<dynamic>?) ?? [];

    // Build map of date -> dominant mood
    final Map<DateTime, String> dayMoods = {};
    final Map<DateTime, List<Map<String, dynamic>>> dayMemories = {};
    for (final d in days) {
      final map = d as Map<String, dynamic>;
      final date = DateTime.parse(map['date'] as String);
      final normalized = DateTime.utc(date.year, date.month, date.day);
      dayMoods[normalized] = map['dominant'] as String? ?? 'neutral';
      dayMemories[normalized] = ((map['memories'] as List<dynamic>?) ?? [])
          .cast<Map<String, dynamic>>();
    }

    // Count mood frequency
    final Map<String, int> moodFreq = {};
    for (final mood in dayMoods.values) {
      moodFreq[mood] = (moodFreq[mood] ?? 0) + 1;
    }
    final sortedMoods = moodFreq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _MoodTimelineBody(
      theme: theme,
      dayMoods: dayMoods,
      dayMemories: dayMemories,
      sortedMoods: sortedMoods,
    );
  }
}

class _MoodTimelineBody extends StatefulWidget {
  final ThemeData theme;
  final Map<DateTime, String> dayMoods;
  final Map<DateTime, List<Map<String, dynamic>>> dayMemories;
  final List<MapEntry<String, int>> sortedMoods;

  const _MoodTimelineBody({
    required this.theme,
    required this.dayMoods,
    required this.dayMemories,
    required this.sortedMoods,
  });

  @override
  State<_MoodTimelineBody> createState() => _MoodTimelineBodyState();
}

class _MoodTimelineBodyState extends State<_MoodTimelineBody> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Calendar
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh.withValues(
              alpha: 0.5,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(12),
          child: TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.now(),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) =>
                _selectedDay != null && isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              HapticFeedback.selectionClick();
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
            },
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              todayDecoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.primary, width: 2),
              ),
              todayTextStyle: TextStyle(color: theme.colorScheme.onSurface),
              selectedDecoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary,
              ),
              defaultTextStyle: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focusedDay) {
                final normalizedDay = DateTime.utc(
                  day.year,
                  day.month,
                  day.day,
                );
                final mood = widget.dayMoods[normalizedDay];
                if (mood != null) {
                  final color =
                      MoodTimelineScreen.moodColors[mood] ??
                      theme.colorScheme.primary;
                  return Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.35),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${day.day}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  );
                }
                return null;
              },
            ),
          ),
        ).animate().fadeIn(duration: 400.ms),

        const SizedBox(height: 20),

        // Selected day's memories
        if (_selectedDay != null) ...[
          Builder(
            builder: (context) {
              final normalizedSelected = DateTime.utc(
                _selectedDay!.year,
                _selectedDay!.month,
                _selectedDay!.day,
              );
              final memories = widget.dayMemories[normalizedSelected];
              final mood = widget.dayMoods[normalizedSelected];

              if (memories == null || memories.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      'No memories on this day',
                      style: GoogleFonts.inter(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ),
                );
              }

              final emoji = MoodTimelineScreen.moodEmojis[mood] ?? '✨';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      Text(
                        mood ?? 'Unknown mood',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${memories.length} memories',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...memories.map((m) {
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
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (MoodTimelineScreen.moodColors[m['mood']] ??
                                      theme.colorScheme.primary)
                                  .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Text(
                              MoodTimelineScreen.moodEmojis[m['mood']] ?? '📷',
                              style: const TextStyle(fontSize: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                m['title'] as String? ?? 'Untitled',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ).animate().fadeIn(duration: 300.ms);
            },
          ),
          const SizedBox(height: 20),
        ],

        // Mood frequency breakdown
        if (widget.sortedMoods.isNotEmpty) ...[
          Text(
            'Your Moods',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...widget.sortedMoods.take(8).toList().asMap().entries.map((entry) {
            final i = entry.key;
            final e = entry.value;
            final color =
                MoodTimelineScreen.moodColors[e.key] ??
                theme.colorScheme.primary;
            final emoji = MoodTimelineScreen.moodEmojis[e.key] ?? '✨';
            final maxCount = widget.sortedMoods.first.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Text(emoji, style: const TextStyle(fontSize: 18)),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      e.key,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: e.value / maxCount,
                        backgroundColor: color.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation(color),
                        minHeight: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 30,
                    child: Text(
                      '${e.value}',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms, delay: (i * 50).ms);
          }),
        ],
      ],
    );
  }
}
