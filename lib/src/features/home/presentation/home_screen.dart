import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../timeline/presentation/timeline_screen.dart';
import '../../ai/presentation/ai_screen.dart';
import '../../../services/upload_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabChanged(int index) {
    if (index == _currentIndex) return;
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final uploadState = ref.watch(uploadStateProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: const [TimelineScreen(), AiScreen()],
          ),

          // Upload status banner
          if (uploadState.status != UploadStatus.idle)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: _UploadBanner(state: uploadState, theme: theme),
              ),
            ),

          // Floating bottom nav
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 0,
            right: 0,
            child: Center(
              child: _BottomNavBar(
                currentIndex: _currentIndex,
                onTap: _onTabChanged,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 56),
        child: FloatingActionButton(
          onPressed: () => _showAddOptions(context),
          child: const Icon(Icons.add_rounded, size: 28),
        ),
      ),
    );
  }

  void _showAddOptions(BuildContext context) {
    final theme = Theme.of(context);
    HapticFeedback.mediumImpact();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text('Add Memory', style: theme.textTheme.titleLarge),
              const SizedBox(height: 20),
              _OptionTile(
                icon: Icons.camera_alt_outlined,
                title: 'Take Photo',
                subtitle: 'Capture a photo with your camera',
                onTap: () {
                  Navigator.pop(context);
                  context.push('/camera', extra: {'mode': 'photo'});
                },
              ),
              const SizedBox(height: 8),
              _OptionTile(
                icon: Icons.videocam_outlined,
                title: 'Record Video',
                subtitle: 'Record a video moment',
                onTap: () {
                  Navigator.pop(context);
                  context.push('/camera', extra: {'mode': 'video'});
                },
              ),
              const SizedBox(height: 8),
              _OptionTile(
                icon: Icons.photo_library_outlined,
                title: 'Upload from Gallery',
                subtitle: 'Choose from your photo library',
                onTap: () {
                  Navigator.pop(context);
                  // TODO: implement gallery picker
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNavBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _NavItem(
                    icon: Icons.home_rounded,
                    isActive: currentIndex == 0,
                    onTap: () => onTap(0),
                  ),
                  const SizedBox(width: 4),
                  _NavItem(
                    icon: Icons.explore_outlined,
                    isActive: currentIndex == 1,
                    onTap: () => onTap(1),
                  ),
                ],
              ),
            ),
          ),
        )
        .animate()
        .fadeIn(duration: 400.ms, curve: Curves.easeOut)
        .slideY(
          begin: 0.3,
          end: 0,
          duration: 500.ms,
          curve: Curves.easeOutCubic,
        );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        width: 52,
        height: 44,
        decoration: BoxDecoration(
          color: isActive
              ? (isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.08))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Icon(
          icon,
          size: 22,
          color: isActive
              ? (isDark ? Colors.white : Colors.black)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.35)
                    : Colors.black.withValues(alpha: 0.3)),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadBanner extends StatelessWidget {
  final UploadState state;
  final ThemeData theme;

  const _UploadBanner({required this.state, required this.theme});

  @override
  Widget build(BuildContext context) {
    final isDone = state.status == UploadStatus.done;
    final isError = state.status == UploadStatus.error;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isError
            ? theme.colorScheme.errorContainer
            : isDone
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.9)
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Status icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isError
                  ? theme.colorScheme.error.withValues(alpha: 0.12)
                  : isDone
                  ? theme.colorScheme.primary.withValues(alpha: 0.12)
                  : theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: isError
                ? Icon(
                    Icons.error_outline,
                    size: 20,
                    color: theme.colorScheme.error,
                  )
                : isDone
                ? Icon(
                    Icons.check_circle_outline,
                    size: 20,
                    color: theme.colorScheme.primary,
                  )
                : SizedBox(
                    width: 20,
                    height: 20,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          // Status text + progress bar
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.statusText,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isError
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurface,
                  ),
                ),
                if (state.status == UploadStatus.uploading &&
                    state.progress > 0) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: state.progress,
                      minHeight: 3,
                      backgroundColor: theme.colorScheme.primary.withValues(
                        alpha: 0.12,
                      ),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Media type icon
          if (!isDone && !isError)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(
                state.isVideo ? Icons.videocam_rounded : Icons.photo_camera,
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
              ),
            ),
        ],
      ),
    );
  }
}
