import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../services/api_service.dart';

final notificationsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  final cached = ref.read(cachedApiProvider);
  final data = await cached.getNotifications();
  return data ?? {};
});

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  static const Map<String, IconData> typeIcons = {
    'on_this_day': Icons.history_rounded,
    'streak': Icons.local_fire_department_rounded,
    'mood_summary': Icons.mood_rounded,
    'nostalgia': Icons.auto_awesome_rounded,
    'milestone': Icons.emoji_events_rounded,
    'vibe_trend': Icons.palette_outlined,
    'color_trend': Icons.color_lens_outlined,
    'capture_prompt': Icons.camera_alt_rounded,
  };

  static const Map<String, Color> typeColors = {
    'on_this_day': Color(0xFF7E57C2),
    'streak': Color(0xFFFF7043),
    'mood_summary': Color(0xFF42A5F5),
    'nostalgia': Color(0xFFFFB74D),
    'milestone': Color(0xFFFFD54F),
    'vibe_trend': Color(0xFFAB47BC),
    'color_trend': Color(0xFF26A69A),
    'capture_prompt': Color(0xFF66BB6A),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifData = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(notificationsProvider),
            icon: const Icon(Icons.refresh_rounded, size: 22),
          ),
        ],
      ),
      body: notifData.when(
        data: (data) {
          final notifications = (data['notifications'] as List<dynamic>?) ?? [];
          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    size: 64,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No notifications yet',
                    style: GoogleFonts.inter(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Keep capturing memories!',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.35,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final notif = notifications[index] as Map<String, dynamic>;
              return _NotificationCard(
                notif: notif,
                theme: theme,
                index: index,
              );
            },
          );
        },
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final Map<String, dynamic> notif;
  final ThemeData theme;
  final int index;

  const _NotificationCard({
    required this.notif,
    required this.theme,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final type = notif['type'] as String? ?? '';
    final title = notif['title'] as String? ?? '';
    final body = notif['body'] as String? ?? '';
    final imageUrl = notif['imageUrl'] as String?;
    final memoryId = notif['memoryId'] as String?;
    final actionRoute = notif['actionRoute'] as String? ?? '/home';

    final icon =
        NotificationsScreen.typeIcons[type] ?? Icons.notifications_rounded;
    final color =
        NotificationsScreen.typeColors[type] ?? theme.colorScheme.primary;

    return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            if (memoryId != null && actionRoute == '/viewer') {
              context.push(
                '/viewer',
                extra: {'memoryId': memoryId, 'initialIndex': 0},
              );
            } else if (actionRoute == '/camera') {
              context.push('/camera');
            } else if (actionRoute == '/mood-timeline') {
              context.push('/mood-timeline');
            } else {
              // Stay on current screen or go home
            }
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.15)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon or image
                if (imageUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, color: color, size: 22),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),

                const SizedBox(width: 12),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        body,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                if (memoryId != null)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
              ],
            ),
          ),
        )
        .animate()
        .fadeIn(duration: 300.ms, delay: (index * 60).ms)
        .slideX(begin: 0.05, end: 0, duration: 300.ms, delay: (index * 60).ms);
  }
}
