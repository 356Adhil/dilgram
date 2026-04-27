import 'dart:ui';
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

enum _MapStyle { voyager, satellite, dark }

class MemoryMapScreen extends ConsumerWidget {
  const MemoryMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mapData = ref.watch(mapDataProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          'Memory Map',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: Colors.white,
            shadows: [
              Shadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 8),
            ],
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_back_rounded, size: 20),
          ),
        ),
      ),
      body: mapData.when(
        data: (data) => _MapBody(data: data),
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
        error: (e, _) => Center(child: Text('Failed to load map: $e')),
      ),
    );
  }
}

class _MapBody extends StatefulWidget {
  final Map<String, dynamic> data;

  const _MapBody({required this.data});

  @override
  State<_MapBody> createState() => _MapBodyState();
}

class _MapBodyState extends State<_MapBody> with TickerProviderStateMixin {
  Map<String, dynamic>? _selectedPin;
  final _mapController = MapController();
  _MapStyle _style = _MapStyle.voyager;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _tileUrl() {
    switch (_style) {
      case _MapStyle.voyager:
        return 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png';
      case _MapStyle.satellite:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      case _MapStyle.dark:
        return 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png';
    }
  }

  List<String> _tileSubdomains() {
    if (_style == _MapStyle.satellite) return const [];
    return const ['a', 'b', 'c', 'd'];
  }

  void _animateToPin(Map<String, dynamic> pin) {
    final lat = (pin['lat'] as num).toDouble();
    final lng = (pin['lng'] as num).toDouble();
    final currentZoom = _mapController.camera.zoom;
    final targetZoom = currentZoom < 13 ? 13.0 : currentZoom;

    // Animated move
    final latTween = Tween<double>(
      begin: _mapController.camera.center.latitude,
      end: lat,
    );
    final lngTween = Tween<double>(
      begin: _mapController.camera.center.longitude,
      end: lng,
    );
    final zoomTween = Tween<double>(begin: currentZoom, end: targetZoom);
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    final curve = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOutCubic,
    );
    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(curve), lngTween.evaluate(curve)),
        zoomTween.evaluate(curve),
      );
    });
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) controller.dispose();
    });
    controller.forward();
  }

  void _fitAllPins(List<dynamic> pins) {
    if (pins.isEmpty) return;
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final p in pins) {
      final lat = (p['lat'] as num).toDouble();
      final lng = (p['lng'] as num).toDouble();
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng)),
        padding: const EdgeInsets.all(60),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pins = (widget.data['pins'] as List<dynamic>?) ?? [];
    final theme = Theme.of(context);

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

    return Stack(
      children: [
        // Map
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
              urlTemplate: _tileUrl(),
              subdomains: _tileSubdomains(),
              userAgentPackageName: 'com.dilgram.app',
              maxZoom: 19,
              retinaMode: _style != _MapStyle.satellite,
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
                  width: isSelected ? 62 : 48,
                  height: isSelected ? 62 : 48,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedPin = pin);
                      _animateToPin(pin);
                    },
                    child: AnimatedScale(
                      scale: isSelected ? 1.0 : 0.85,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Pulse ring on selected
                          if (isSelected)
                            AnimatedBuilder(
                              animation: _pulseController,
                              builder: (_, child) => Container(
                                width: 62 + (_pulseController.value * 14),
                                height: 62 + (_pulseController.value * 14),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: 0.4 - _pulseController.value * 0.3,
                                    ),
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          // Shadow
                          Container(
                            width: isSelected ? 56 : 44,
                            height: isSelected ? 56 : 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: isSelected
                                      ? theme.colorScheme.primary.withValues(
                                          alpha: 0.35,
                                        )
                                      : Colors.black.withValues(alpha: 0.25),
                                  blurRadius: isSelected ? 12 : 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                          ),
                          // Marker image
                          Container(
                            width: isSelected ? 56 : 44,
                            height: isSelected ? 56 : 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : Colors.white,
                                width: isSelected ? 3 : 2.5,
                              ),
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
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),

        // Top gradient for immersive feel
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 120,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        // Right-side controls
        Positioned(
          right: 14,
          top: MediaQuery.of(context).padding.top + 56,
          child: Column(
            children: [
              // Map style picker
              _MapControlButton(
                icon: switch (_style) {
                  _MapStyle.voyager => Icons.map_outlined,
                  _MapStyle.satellite => Icons.satellite_alt,
                  _MapStyle.dark => Icons.dark_mode_outlined,
                },
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _style = _MapStyle
                        .values[(_style.index + 1) % _MapStyle.values.length];
                  });
                },
              ),
              const SizedBox(height: 8),
              // Fit all
              _MapControlButton(
                icon: Icons.fit_screen_rounded,
                onTap: () {
                  HapticFeedback.selectionClick();
                  _fitAllPins(pins);
                },
              ),
              const SizedBox(height: 8),
              // Zoom in
              _MapControlButton(
                icon: Icons.add_rounded,
                onTap: () {
                  final z = _mapController.camera.zoom;
                  _mapController.move(
                    _mapController.camera.center,
                    (z + 1).clamp(1.0, 19.0),
                  );
                },
              ),
              const SizedBox(height: 4),
              // Zoom out
              _MapControlButton(
                icon: Icons.remove_rounded,
                onTap: () {
                  final z = _mapController.camera.zoom;
                  _mapController.move(
                    _mapController.camera.center,
                    (z - 1).clamp(1.0, 19.0),
                  );
                },
              ),
            ],
          ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
        ),

        // Pin count badge
        Positioned(
          bottom: _selectedPin != null ? 130 : 32,
          left: 14,
          child: AnimatedSlide(
            offset: Offset.zero,
            duration: const Duration(milliseconds: 250),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${pins.length} place${pins.length != 1 ? 's' : ''}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // Selected pin card
        if (_selectedPin != null)
          Positioned(
            bottom: 32,
            left: 14,
            right: 14,
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.brightness == Brightness.dark
                          ? Colors.black.withValues(alpha: 0.55)
                          : Colors.white.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: theme.brightness == Brightness.dark
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (_selectedPin!['thumbnail'] != null)
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CachedNetworkImage(
                                imageUrl: _selectedPin!['thumbnail'] as String,
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        const SizedBox(width: 14),
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
                                  color: theme.colorScheme.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.place_outlined,
                                    size: 13,
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: 0.7,
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
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.15, end: 0),
          ),
      ],
    );
  }
}

class _MapControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MapControlButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}
