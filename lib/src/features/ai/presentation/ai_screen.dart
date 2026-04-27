import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../timeline/domain/memory_model.dart';
import '../../../services/api_service.dart';

// Discover data provider
final discoverProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  final api = ref.read(apiServiceProvider);
  return api.getDiscover();
});

class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key});

  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends ConsumerState<AiScreen> {
  final _chatController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _isSending = false;

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
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
        String errorMsg = 'Sorry, something went wrong. Try again!';
        if (e is DioException) {
          final serverError = e.response?.data;
          if (serverError is Map && serverError['error'] != null) {
            errorMsg = '${serverError['error']}';
          } else if (e.type == DioExceptionType.connectionError) {
            errorMsg = 'Cannot connect to server. Check your internet.';
          }
        }
        setState(() {
          _messages.add(_ChatMessage(text: errorMsg, isUser: false));
          _isSending = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final discover = ref.watch(discoverProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Discover',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(discoverProvider),
            icon: const Icon(Icons.refresh_rounded, size: 22),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: discover.when(
              data: (data) => _buildContent(data, theme),
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              error: (e, _) => _buildContent({}, theme),
            ),
          ),
          _buildChatInput(theme),
        ],
      ),
    );
  }

  Widget _buildContent(Map<String, dynamic> data, ThemeData theme) {
    final featured = data['featured'] as Map<String, dynamic>?;
    final weeklyRecap = data['weeklyRecap'] as Map<String, dynamic>?;
    final monthlyRecap = data['monthlyRecap'] as Map<String, dynamic>?;
    final onThisDay =
        (data['onThisDay'] as List<dynamic>?)
            ?.map((e) => Memory.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final people = (data['people'] as List<dynamic>?) ?? [];
    final places = (data['places'] as List<dynamic>?) ?? [];
    final stats = data['stats'] as Map<String, dynamic>?;

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: [
        // Featured Memory
        if (featured != null)
          _FeaturedCard(featured: featured)
              .animate()
              .fadeIn(duration: 400.ms)
              .slideY(begin: 0.05, end: 0, duration: 400.ms),

        if (featured != null) const SizedBox(height: 16),

        // Stats
        if (stats != null)
          _StatsCard(stats: stats)
              .animate()
              .fadeIn(duration: 400.ms, delay: 100.ms)
              .slideY(begin: 0.05, end: 0, duration: 400.ms, delay: 100.ms),

        if (stats != null) const SizedBox(height: 16),

        // Weekly Recap
        if (weeklyRecap != null) ...[
          _RecapCard(
                title: 'Weekly Recap',
                icon: Icons.date_range_rounded,
                recap: weeklyRecap,
                onTap: () =>
                    context.push('/recap', extra: {'period': 'weekly'}),
              )
              .animate()
              .fadeIn(duration: 400.ms, delay: 150.ms)
              .slideY(begin: 0.05, end: 0, duration: 400.ms, delay: 150.ms),
          const SizedBox(height: 12),
        ],

        // Monthly Recap
        if (monthlyRecap != null) ...[
          _RecapCard(
                title: 'Monthly Recap',
                icon: Icons.calendar_month_rounded,
                recap: monthlyRecap,
                onTap: () =>
                    context.push('/recap', extra: {'period': 'monthly'}),
              )
              .animate()
              .fadeIn(duration: 400.ms, delay: 200.ms)
              .slideY(begin: 0.05, end: 0, duration: 400.ms, delay: 200.ms),
          const SizedBox(height: 16),
        ],

        // People
        if (people.isNotEmpty) ...[
          _SectionTitle(title: 'People'),
          const SizedBox(height: 10),
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: people.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final person = people[index] as Map<String, dynamic>;
                final label = person['label'] as String? ?? 'Unknown';
                final count = person['count'] as int? ?? 0;
                final thumbnail = person['thumbnail'] as String?;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.push('/person', extra: {'label': label});
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.12,
                          ),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.2,
                            ),
                            width: 2,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: thumbnail != null
                            ? CachedNetworkImage(
                                imageUrl: thumbnail,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Center(
                                  child: Text(
                                    label.isNotEmpty
                                        ? label[0].toUpperCase()
                                        : '?',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                                errorWidget: (_, __, ___) => Center(
                                  child: Text(
                                    label.isNotEmpty
                                        ? label[0].toUpperCase()
                                        : '?',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              )
                            : Center(
                                child: Text(
                                  label.isNotEmpty
                                      ? label[0].toUpperCase()
                                      : '?',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: 64,
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        '$count',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(
                  duration: 300.ms,
                  delay: (250 + index * 50).ms,
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Places
        if (places.isNotEmpty) ...[
          _SectionTitle(title: 'Places'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: places.map((p) {
              final place = p as Map<String, dynamic>;
              final name = place['name'] as String? ?? '';
              final count = place['count'] as int? ?? 0;
              return ActionChip(
                avatar: const Icon(Icons.place_outlined, size: 16),
                label: Text(
                  '$name ($count)',
                  style: GoogleFonts.inter(fontSize: 12),
                ),
                onPressed: () {
                  // Could navigate to search with location filter
                },
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ).animate().fadeIn(duration: 400.ms, delay: 300.ms),
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
                    .fadeIn(duration: 350.ms, delay: (350 + index * 60).ms)
                    .slideX(
                      begin: 0.1,
                      end: 0,
                      duration: 350.ms,
                      delay: (350 + index * 60).ms,
                    );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Chat messages
        if (_messages.isNotEmpty) ...[
          _SectionTitle(title: 'Chat'),
          const SizedBox(height: 8),
          ..._messages.map((msg) {
            return _ChatBubble(message: msg)
                .animate()
                .fadeIn(duration: 250.ms)
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

  Widget _buildChatInput(ThemeData theme) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        76,
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

// --- Models ---

class _ChatMessage {
  final String text;
  final bool isUser;
  _ChatMessage({required this.text, required this.isUser});
}

// --- Widgets ---

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  final Map<String, dynamic> featured;
  const _FeaturedCard({required this.featured});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final memory = Memory.fromJson(featured);
    final item = memory.mediaItems.isNotEmpty ? memory.mediaItems.first : null;
    final url = item != null
        ? (item.isVideo ? (item.thumbnailUrl ?? item.url) : item.url)
        : null;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        context.push(
          '/viewer',
          extra: {'memoryId': memory.id, 'initialIndex': 0},
        );
      },
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: theme.colorScheme.surfaceContainerHigh,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url != null)
                CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      Container(color: theme.colorScheme.surfaceContainerHigh),
                ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.65),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        size: 12,
                        color: theme.colorScheme.onPrimary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Featured',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 14,
                left: 14,
                right: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (memory.title != null && memory.title!.isNotEmpty)
                      Text(
                        memory.title!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    if (memory.location?.name != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.place,
                              size: 12,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              memory.location!.name!,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(
            value: '${stats['totalMemories'] ?? 0}',
            label: 'Memories',
            icon: Icons.collections_outlined,
          ),
          _StatItem(
            value: '${stats['totalPhotos'] ?? 0}',
            label: 'Photos',
            icon: Icons.photo_outlined,
          ),
          _StatItem(
            value: '${stats['totalVideos'] ?? 0}',
            label: 'Videos',
            icon: Icons.videocam_outlined,
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
      children: [
        Icon(
          icon,
          size: 18,
          color: theme.colorScheme.primary.withValues(alpha: 0.7),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

class _RecapCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Map<String, dynamic> recap;
  final VoidCallback onTap;

  const _RecapCard({
    required this.title,
    required this.icon,
    required this.recap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = recap['summary'] as String? ?? '';
    final memoryCount = recap['memoryCount'] as int? ?? 0;
    final locations =
        (recap['locations'] as List<dynamic>?)?.cast<String>() ?? [];

    // Build a summary from available data if none provided
    final displaySummary = summary.isNotEmpty
        ? summary
        : locations.isNotEmpty
        ? '${locations.take(3).join(', ')}${locations.length > 3 ? '...' : ''}'
        : '';

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: theme.colorScheme.primary, size: 22),
            ),
            const SizedBox(width: 14),
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
                  ),
                  if (displaySummary.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        displaySummary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ),
                  if (memoryCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '$memoryCount memories',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ],
        ),
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
