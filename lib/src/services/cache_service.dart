import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final cacheServiceProvider = Provider<CacheService>((ref) => CacheService());

/// Lightweight SWR (stale-while-revalidate) cache.
///
/// - In-memory map for instant reads within the session.
/// - JSON file on disk so cached data survives restarts.
/// - Every entry has a TTL; stale entries are still returned but the caller
///   knows to revalidate in the background.
/// - Max entries cap prevents unbounded disk growth.
class CacheService {
  static const int _maxEntries = 50;
  static const Duration _defaultTtl = Duration(minutes: 10);

  final Map<String, _CacheEntry> _mem = {};
  bool _diskLoaded = false;
  Directory? _cacheDir;

  // ── public API ──────────────────────────────────────────────

  /// Returns cached data for [key], or null if nothing cached.
  /// [fresh] is true when the entry hasn't expired yet.
  Future<CacheResult?> get(String key) async {
    await _ensureDisk();
    final entry = _mem[key];
    if (entry == null) return null;
    final fresh = DateTime.now().isBefore(entry.expiresAt);
    return CacheResult(data: entry.data, isFresh: fresh);
  }

  /// Store [data] under [key] with an optional [ttl].
  Future<void> put(
    String key,
    Map<String, dynamic> data, {
    Duration ttl = _defaultTtl,
  }) async {
    await _ensureDisk();
    _mem[key] = _CacheEntry(
      data: data,
      expiresAt: DateTime.now().add(ttl),
      storedAt: DateTime.now(),
    );
    _evictIfNeeded();
    await _writeDisk();
  }

  /// Remove a single key.
  Future<void> remove(String key) async {
    _mem.remove(key);
    await _writeDisk();
  }

  /// Wipe everything (e.g. on logout).
  Future<void> clear() async {
    _mem.clear();
    final file = await _file();
    if (await file.exists()) {
      await file.delete();
    }
  }

  // ── disk persistence ────────────────────────────────────────

  Future<void> _ensureDisk() async {
    if (_diskLoaded) return;
    _diskLoaded = true;
    try {
      final file = await _file();
      if (await file.exists()) {
        final raw = await file.readAsString();
        final map = jsonDecode(raw) as Map<String, dynamic>;
        for (final e in map.entries) {
          final v = e.value as Map<String, dynamic>;
          final expiresAt = DateTime.parse(v['expiresAt'] as String);
          // Drop entries that are way too old (> 24 h)
          if (DateTime.now().difference(expiresAt) >
              const Duration(hours: 24)) {
            continue;
          }
          _mem[e.key] = _CacheEntry(
            data: v['data'] as Map<String, dynamic>,
            expiresAt: expiresAt,
            storedAt: DateTime.parse(v['storedAt'] as String),
          );
        }
      }
    } catch (_) {
      // Corrupt cache? Just ignore and start fresh.
    }
  }

  Future<File> _file() async {
    _cacheDir ??= await getTemporaryDirectory();
    return File('${_cacheDir!.path}/dilgram_cache.json');
  }

  Future<void> _writeDisk() async {
    try {
      final map = <String, dynamic>{};
      for (final e in _mem.entries) {
        map[e.key] = {
          'data': e.value.data,
          'expiresAt': e.value.expiresAt.toIso8601String(),
          'storedAt': e.value.storedAt.toIso8601String(),
        };
      }
      final file = await _file();
      await file.writeAsString(jsonEncode(map));
    } catch (_) {}
  }

  void _evictIfNeeded() {
    if (_mem.length <= _maxEntries) return;
    // Remove oldest entries first
    final sorted = _mem.entries.toList()
      ..sort((a, b) => a.value.storedAt.compareTo(b.value.storedAt));
    while (_mem.length > _maxEntries) {
      _mem.remove(sorted.removeAt(0).key);
    }
  }
}

class _CacheEntry {
  final Map<String, dynamic> data;
  final DateTime expiresAt;
  final DateTime storedAt;
  _CacheEntry({
    required this.data,
    required this.expiresAt,
    required this.storedAt,
  });
}

class CacheResult {
  final Map<String, dynamic> data;
  final bool isFresh;
  const CacheResult({required this.data, required this.isFresh});
}
