import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../timeline/application/timeline_provider.dart';
import '../../timeline/domain/memory_model.dart';
import '../../../services/api_service.dart';

// AI highlights state
final aiHighlightsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  final api = ref.read(apiServiceProvider);
  return api.getHighlights();
});

class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key});

  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends ConsumerState<AiScreen> {
  final _chatController = TextEditingController();
  final _chatScrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _isSending = false;

  @override
  void dispose() {
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _isSending = true;
    });
    _chatController.clear();
    _scrollToBottom();

    try {
      final reply = await ref.read(apiServiceProvider).chatWithAi(text);
      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage(text: reply, isUser: false));
          _isSending = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(
            _ChatMessage(
              text: 'Sorry, I couldn\'t process that. Try again!',
              isUser: false,
            ),
          );
          _isSending = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _analyzeMemory(Memory memory) async {
    HapticFeedback.mediumImpact();
    try {
      final result = await ref
          .read(apiServiceProvider)
          .analyzeMemory(memory.id, apply: true);

      if (mounted) {
        // Update local state
        final updated = memory.copyWith(
          title: result['title'] as String?,
          description: result['description'] as String?,
        );
        ref.read(timelineProvider.notifier).updateMemory(updated);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✨ "${result['title']}"'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to analyze. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlights = ref.watch(aiHighlightsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'AI Assistant',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          // Content area
          Expanded(
            child: highlights.when(
              data: (data) => _buildContent(data, theme),
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              error: (e, _) => _buildContent({}, theme),
            ),
          ),

          // Chat input
          _buildChatInput(theme),
        ],
      ),
    );
  }

  Widget _buildContent(Map<String, dynamic> data, ThemeData theme) {
    final onThisDay =
        (data['onThisDay'] as List<dynamic>?)
            ?.map((e) => Memory.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final weeklyStory = data['weeklyStory'] as Map<String, dynamic>?;
    final stats = data['stats'] as Map<String, dynamic>?;
    final timeline = ref.watch(timelineProvider);

    return ListView(
      controller: _chatScrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: [
        // Stats overview
        if (stats != null)
          _StatsCard(stats: stats)
              .animate()
              .fadeIn(duration: 400.ms, curve: Curves.easeOut)
              .slideY(begin: 0.05, end: 0, duration: 400.ms),

        const SizedBox(height: 16),

        // Weekly story from AI
        if (weeklyStory != null) ...[
          _WeeklyStoryCard(story: weeklyStory)
              .animate()
              .fadeIn(duration: 400.ms, delay: 100.ms, curve: Curves.easeOut)
              .slideY(begin: 0.05, end: 0, duration: 400.ms, delay: 100.ms),
          const SizedBox(height: 16),
        ],

        // On This Day
        if (onThisDay.isNotEmpty) ...[
          _SectionTitle(title: 'On This Day'),
          const SizedBox(height: 8),
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: onThisDay.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                return _OnThisDayCard(
                      memory: onThisDay[index],
                      onTap: () => context.push(
                        '/viewer',
                        extra: {
                          'memoryId': onThisDay[index].id,
                          'initialIndex': 0,
                        },
                      ),
                    )
                    .animate()
                    .fadeIn(
                      duration: 350.ms,
                      delay: (200 + index * 60).ms,
                      curve: Curves.easeOut,
                    )
                    .slideX(
                      begin: 0.1,
                      end: 0,
                      duration: 350.ms,
                      delay: (200 + index * 60).ms,
                    );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],

        // AI-powered actions on recent memories
        _SectionTitle(title: 'Auto-Caption'),
        const SizedBox(height: 8),
        ..._buildUntitledMemories(timeline.memories, theme),

        // Chat messages
        if (_messages.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionTitle(title: 'Chat'),
          const SizedBox(height: 8),
          ..._messages.asMap().entries.map((entry) {
            return _ChatBubble(message: entry.value)
                .animate()
                .fadeIn(duration: 250.ms, curve: Curves.easeOut)
                .slideY(begin: 0.1, end: 0, duration: 250.ms);
          }),
          if (_isSending)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _TypingIndicator(),
              ),
            ),
        ],

        const SizedBox(height: 80),
      ],
    );
  }

  List<Widget> _buildUntitledMemories(List<Memory> memories, ThemeData theme) {
    final untitled = memories
        .where(
          (m) =>
              (m.title == null || m.title!.isEmpty) &&
              m.mediaItems.any((i) => i.isPhoto),
        )
        .take(5)
        .toList();

    if (untitled.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'All your memories have captions! 🎉',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      ];
    }

    return untitled
        .map(
          (memory) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _UntitledMemoryTile(
              memory: memory,
              onAnalyze: () => _analyzeMemory(memory),
            ),
          ),
        )
        .toList();
  }

  Widget _buildChatInput(ThemeData theme) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        MediaQuery.of(context).padding.bottom + 72,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chatController,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: 'Ask about your memories...',
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHigh.withValues(
                  alpha: 0.5,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_upward_rounded,
                color: theme.colorScheme.onPrimary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  _ChatMessage({required this.text, required this.isUser});
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurface,
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _StatsCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.08),
            theme.colorScheme.primary.withValues(alpha: 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                color: theme.colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Your Memory Vault',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatItem(
                value: '${stats['totalMemories'] ?? 0}',
                label: 'Memories',
                icon: Icons.collections_outlined,
              ),
              const SizedBox(width: 24),
              _StatItem(
                value: '${stats['totalPhotos'] ?? 0}',
                label: 'Photos',
                icon: Icons.photo_outlined,
              ),
              const SizedBox(width: 24),
              _StatItem(
                value: '${stats['totalVideos'] ?? 0}',
                label: 'Videos',
                icon: Icons.videocam_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;

  const _StatItem({
    required this.value,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: theme.colorScheme.primary.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 4),
            Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

class _WeeklyStoryCard extends StatelessWidget {
  final Map<String, dynamic> story;
  const _WeeklyStoryCard({required this.story});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_stories,
                color: theme.colorScheme.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                story['theme'] ?? 'This Week',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            story['story'] ?? '',
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.6,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnThisDayCard extends StatelessWidget {
  final Memory memory;
  final VoidCallback onTap;

  const _OnThisDayCard({required this.memory, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = memory.mediaItems.isNotEmpty ? memory.mediaItems.first : null;
    final url = item != null
        ? (item.isVideo ? (item.thumbnailUrl ?? item.url) : item.url)
        : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: theme.colorScheme.surfaceContainerHigh,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url != null)
                CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
              else
                Center(
                  child: Icon(
                    Icons.image_outlined,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                  ),
                ),
              // Year label
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.6),
                      ],
                    ),
                  ),
                  child: Text(
                    '${memory.createdAt.year}',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UntitledMemoryTile extends StatefulWidget {
  final Memory memory;
  final VoidCallback onAnalyze;

  const _UntitledMemoryTile({required this.memory, required this.onAnalyze});

  @override
  State<_UntitledMemoryTile> createState() => _UntitledMemoryTileState();
}

class _UntitledMemoryTileState extends State<_UntitledMemoryTile> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.memory.mediaItems.isNotEmpty
        ? widget.memory.mediaItems.first
        : null;
    final url = item != null
        ? (item.isVideo ? (item.thumbnailUrl ?? item.url) : item.url)
        : null;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          // Thumbnail
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: theme.colorScheme.surfaceContainerHigh,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: url != null
                  ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
                  : Icon(
                      Icons.image_outlined,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Untitled memory',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _formatDate(widget.memory.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
          // AI button
          GestureDetector(
            onTap: _loading
                ? null
                : () {
                    setState(() => _loading = true);
                    widget.onAnalyze();
                    Future.delayed(const Duration(seconds: 3), () {
                      if (mounted) setState(() => _loading = false);
                    });
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: _loading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Caption',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class _ChatBubble extends StatelessWidget {
  final _ChatMessage message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
        ),
        child: Text(
          message.text,
          style: GoogleFonts.inter(
            fontSize: 14,
            height: 1.4,
            color: isUser
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomRight: Radius.circular(18),
          bottomLeft: Radius.circular(4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
              )
              .animate(onPlay: (c) => c.repeat())
              .fadeIn(duration: 400.ms, delay: (i * 150).ms)
              .then()
              .fadeOut(duration: 400.ms);
        }),
      ),
    );
  }
}
