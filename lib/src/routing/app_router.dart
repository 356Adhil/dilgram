import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/presentation/lock_screen.dart';
import '../features/auth/presentation/setup_pin_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/camera/presentation/camera_screen.dart';
import '../features/camera/presentation/preview_screen.dart';
import '../features/media_viewer/presentation/media_viewer_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/ai/presentation/recap_screen.dart';
import '../features/ai/presentation/person_memories_screen.dart';
import '../features/ai/presentation/mood_timeline_screen.dart';
import '../features/ai/presentation/color_memories_screen.dart';
import '../features/ai/presentation/vibe_memories_screen.dart';
import '../features/ai/presentation/journal_screen.dart';
import '../features/ai/presentation/mashup_screen.dart';
import '../features/map/presentation/memory_map_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/lock',
    routes: [
      GoRoute(
        path: '/lock',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const LockScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        path: '/setup',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const SetupPinScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        path: '/home',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const HomeScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        path: '/camera',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const CameraScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            );
          },
        ),
      ),
      GoRoute(
        path: '/preview',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return CustomTransitionPage(
            key: state.pageKey,
            child: PreviewScreen(
              filePath: extra['filePath'] as String,
              isVideo: extra['isVideo'] as bool,
            ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
          );
        },
      ),
      GoRoute(
        path: '/viewer',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return CustomTransitionPage(
            key: state.pageKey,
            child: MediaViewerScreen(
              memoryId: extra['memoryId'] as String,
              initialIndex: extra['initialIndex'] as int? ?? 0,
            ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
          );
        },
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const SettingsScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            );
          },
        ),
      ),
      GoRoute(
        path: '/recap',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return CustomTransitionPage(
            key: state.pageKey,
            child: RecapScreen(period: extra['period'] as String? ?? 'weekly'),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
          );
        },
      ),
      GoRoute(
        path: '/person',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return CustomTransitionPage(
            key: state.pageKey,
            child: PersonMemoriesScreen(label: extra['label'] as String? ?? ''),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position:
                        Tween<Offset>(
                          begin: const Offset(1, 0),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                    child: child,
                  );
                },
          );
        },
      ),
      GoRoute(
        path: '/mood-timeline',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const MoodTimelineScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            );
          },
        ),
      ),
      GoRoute(
        path: '/map',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const MemoryMapScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            );
          },
        ),
      ),
      GoRoute(
        path: '/color',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return CustomTransitionPage(
            key: state.pageKey,
            child: ColorMemoriesScreen(
              hex: extra['hex'] as String? ?? '#000000',
            ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position:
                        Tween<Offset>(
                          begin: const Offset(1, 0),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                    child: child,
                  );
                },
          );
        },
      ),
      GoRoute(
        path: '/vibe',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return CustomTransitionPage(
            key: state.pageKey,
            child: VibeMemoriesScreen(vibe: extra['vibe'] as String? ?? ''),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position:
                        Tween<Offset>(
                          begin: const Offset(1, 0),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                    child: child,
                  );
                },
          );
        },
      ),
      GoRoute(
        path: '/journal',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return CustomTransitionPage(
            key: state.pageKey,
            child: JournalScreen(initialDate: extra?['date'] as String?),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
          );
        },
      ),
      GoRoute(
        path: '/mashup',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const MashupScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            );
          },
        ),
      ),
      GoRoute(
        path: '/notifications',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const NotificationsScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            );
          },
        ),
      ),
    ],
  );
});
