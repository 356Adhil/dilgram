import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../services/api_service.dart';

final mapDataProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  final cached = ref.read(cachedApiProvider);
  final data = await cached.getMemoryMap();
  return data ?? {};
});

class MemoryMapScreen extends ConsumerWidget {
  const MemoryMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mapData = ref.watch(mapDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Memory Map',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
      ),
      body: mapData.when(
        data: (data) => _MapBody(data: data, theme: theme),
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
        error: (e, _) => Center(child: Text('Failed to load map: $e')),
      ),
    );
  }
}

class _MapBody extends StatefulWidget {
  final Map<String, dynamic> data;
  final ThemeData theme;

  const _MapBody({required this.data, required this.theme});

  @override
  State<_MapBody> createState() => _MapBodyState();
}

class _MapBodyState extends State<_MapBody> {
  Map<String, dynamic>? _selectedPin;
  final _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    final pins = (widget.data['pins'] as List<dynamic>?) ?? [];
    final theme = widget.theme;

    if (pins.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.map_outlined,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No geotagged memories yet',
              style: GoogleFonts.inter(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enable location when capturing memories',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      );
    }

    // Calculate initial center from pins
    double avgLat = 0, avgLng = 0;
    for (final p in pins) {
      avgLat += (p['lat'] as num).toDouble();
      avgLng += (p['lng'] as num).toDouble();
    }
    avgLat /= pins.length;
    avgLng /= pins.length;

    final isDark = theme.brightness == Brightness.dark;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: LatLng(avgLat, avgLng),
            initialZoom: 10,
            onTap: (_, __) {
              setState(() => _selectedPin = null);
            },
          ),
          children: [
            TileLayer(
              urlTemplate: isDark
                  ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png'
                  : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.dilgram.app',
              maxZoom: 19,
              retinaMode: true,
            ),
            MarkerLayer(
              markers: pins.map((p) {
                final pin = p as Map<String, dynamic>;
                final lat = (pin['lat'] as num).toDouble();
                final lng = (pin['lng'] as num).toDouble();
                final thumbnail = pin['thumbnail'] as String?;
                final isSelected =
                    _selectedPin != null && _selectedPin!['id'] == pin['id'];

                return Marker(
                  point: LatLng(lat, lng),
                  width: isSelected ? 56 : 44,
                  height: isSelected ? 56 : 44,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedPin = pin);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? theme.colorScheme.primary
                              : Colors.white,
                          width: isSelected ? 3 : 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: thumbnail != null
                          ? CachedNetworkImage(
                              imageUrl: thumbnail,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: theme.colorScheme.primary,
                                child: const Icon(
                                  Icons.photo,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            )
                          : Container(
                              color: theme.colorScheme.primary,
                              child: const Icon(
                                Icons.place,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),

        // Pin count badge
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Text(
              '${pins.length} memories',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ).animate().fadeIn(duration: 300.ms),
        ),

        // Selected pin card
        if (_selectedPin != null)
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                context.push(
                  '/viewer',
                  extra: {
                    'memoryId': _selectedPin!['id'].toString(),
                    'initialIndex': 0,
                  },
                );
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    if (_selectedPin!['thumbnail'] != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedNetworkImage(
                          imageUrl: _selectedPin!['thumbnail'] as String,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _selectedPin!['title'] as String? ??
                                'Untitled Memory',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: 14,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _selectedPin!['name'] as String? ??
                                      'Unknown location',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.5),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
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
            ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.2, end: 0),
          ),
      ],
    );
  }
}
