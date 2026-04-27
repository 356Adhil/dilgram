import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/api_constants.dart';
import 'cache_service.dart';

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

final cachedApiProvider = Provider<CachedApiService>((ref) {
  return CachedApiService(
    ref.read(apiServiceProvider),
    ref.read(cacheServiceProvider),
  );
});

class ApiService {
  late final Dio _dio;
  final _storage = const FlutterSecureStorage();

  ApiService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: ApiConstants.connectionTimeout,
        receiveTimeout: ApiConstants.receiveTimeout,
        headers: {'Content-Type': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: 'auth_token');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          handler.next(error);
        },
      ),
    );
  }

  Future<void> setToken(String token) async {
    await _storage.write(key: 'auth_token', value: token);
  }

  Future<void> clearToken() async {
    await _storage.delete(key: 'auth_token');
  }

  Future<String?> getToken() async {
    return _storage.read(key: 'auth_token');
  }

  // Auth
  Future<Map<String, dynamic>> setupPin(String pin) async {
    final response = await _dio.post(ApiConstants.setupPin, data: {'pin': pin});
    return response.data;
  }

  Future<Map<String, dynamic>> verifyPin(String pin) async {
    final response = await _dio.post(
      ApiConstants.verifyPin,
      data: {'pin': pin},
    );
    return response.data;
  }

  // Memories
  Future<List<dynamic>> getMemories({int page = 1, int limit = 20}) async {
    final response = await _dio.get(
      ApiConstants.memories,
      queryParameters: {'page': page, 'limit': limit},
    );
    return response.data['memories'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> getMemory(String id) async {
    final response = await _dio.get(ApiConstants.memory(id));
    return response.data;
  }

  Future<Map<String, dynamic>> createMemory({
    String? title,
    String? description,
    required List<File> files,
    required List<String> types,
    double? latitude,
    double? longitude,
    String? locationName,
    void Function(int, int)? onProgress,
  }) async {
    final formData = FormData();

    if (title != null) formData.fields.add(MapEntry('title', title));
    if (description != null) {
      formData.fields.add(MapEntry('description', description));
    }
    if (latitude != null) {
      formData.fields.add(MapEntry('latitude', latitude.toString()));
    }
    if (longitude != null) {
      formData.fields.add(MapEntry('longitude', longitude.toString()));
    }
    if (locationName != null) {
      formData.fields.add(MapEntry('locationName', locationName));
    }

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final fileName = file.path.split('/').last;
      formData.files.add(
        MapEntry(
          'media',
          await MultipartFile.fromFile(file.path, filename: fileName),
        ),
      );
      formData.fields.add(MapEntry('types', types[i]));
    }

    final response = await _dio.post(
      ApiConstants.memories,
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
        sendTimeout: ApiConstants.uploadTimeout,
        receiveTimeout: ApiConstants.uploadTimeout,
      ),
      onSendProgress: onProgress,
    );
    return response.data;
  }

  Future<Map<String, dynamic>> updateMemory(
    String id, {
    String? title,
    String? description,
  }) async {
    final response = await _dio.put(
      ApiConstants.memory(id),
      data: {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
      },
    );
    return response.data;
  }

  Future<void> deleteMemory(String id) async {
    await _dio.delete(ApiConstants.memory(id));
  }

  Future<Map<String, dynamic>> addMedia(
    String memoryId, {
    required List<File> files,
    required List<String> types,
    void Function(int, int)? onProgress,
  }) async {
    final formData = FormData();

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final fileName = file.path.split('/').last;
      formData.files.add(
        MapEntry(
          'media',
          await MultipartFile.fromFile(file.path, filename: fileName),
        ),
      );
      formData.fields.add(MapEntry('types', types[i]));
    }

    final response = await _dio.post(
      ApiConstants.memoryMedia(memoryId),
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
        sendTimeout: ApiConstants.uploadTimeout,
        receiveTimeout: ApiConstants.uploadTimeout,
      ),
      onSendProgress: onProgress,
    );
    return response.data;
  }

  Future<void> deleteMedia(String memoryId, String mediaId) async {
    await _dio.delete(ApiConstants.deleteMedia(memoryId, mediaId));
  }

  Future<Map<String, dynamic>> getStats() async {
    final response = await _dio.get(ApiConstants.memoriesStats);
    return response.data;
  }

  // Favorites
  Future<Map<String, dynamic>> toggleFavorite(String id) async {
    final response = await _dio.patch(ApiConstants.memoryFavorite(id));
    return response.data;
  }

  // Search
  Future<List<dynamic>> searchMemories(String query) async {
    final response = await _dio.get(
      ApiConstants.memoriesSearch,
      queryParameters: {'q': query},
    );
    return response.data['memories'] as List<dynamic>;
  }

  // Batch Delete
  Future<void> batchDeleteMemories(List<String> ids) async {
    await _dio.post(ApiConstants.memoriesBatchDelete, data: {'ids': ids});
  }

  // AI
  Future<bool> getAiStatus() async {
    try {
      final response = await _dio.get(ApiConstants.aiStatus);
      return response.data['enabled'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> analyzeMemory(
    String memoryId, {
    bool apply = false,
  }) async {
    final response = await _dio.post(
      '${ApiConstants.aiAnalyze(memoryId)}${apply ? '?apply=true' : ''}',
    );
    return response.data;
  }

  Future<Map<String, dynamic>> getHighlights() async {
    final response = await _dio.get(ApiConstants.aiHighlights);
    return response.data;
  }

  Future<String> chatWithAi(String message) async {
    final response = await _dio.post(
      ApiConstants.aiChat,
      data: {'message': message},
    );
    return response.data['reply'] as String;
  }

  // Discover
  Future<Map<String, dynamic>> getDiscover() async {
    final response = await _dio.get(ApiConstants.aiDiscover);
    return response.data;
  }

  // Weekly Recap
  Future<Map<String, dynamic>> getWeeklyRecap() async {
    final response = await _dio.get(ApiConstants.aiWeeklyRecap);
    return response.data;
  }

  // Monthly Recap
  Future<Map<String, dynamic>> getMonthlyRecap() async {
    final response = await _dio.get(ApiConstants.aiMonthlyRecap);
    return response.data;
  }

  // Grouped Memories
  Future<Map<String, dynamic>> getGroupedMemories({
    String by = 'location',
  }) async {
    final response = await _dio.get(
      ApiConstants.memoriesGrouped,
      queryParameters: {'by': by},
    );
    return response.data;
  }

  // Memory Map
  Future<Map<String, dynamic>> getMemoryMap() async {
    final response = await _dio.get(ApiConstants.memoriesMap);
    return response.data;
  }

  // AI Journal
  Future<Map<String, dynamic>> getJournal({String? date}) async {
    final response = await _dio.get(
      ApiConstants.aiJournal,
      queryParameters: date != null ? {'date': date} : null,
      options: Options(receiveTimeout: ApiConstants.aiTimeout),
    );
    return response.data;
  }

  // AI Mashup
  Future<Map<String, dynamic>> getMashup({
    String? person,
    String? place,
    String? vibe,
    String? dateFrom,
    String? dateTo,
  }) async {
    final response = await _dio.post(
      ApiConstants.aiMashup,
      data: {
        if (person != null) 'person': person,
        if (place != null) 'place': place,
        if (vibe != null) 'vibe': vibe,
        if (dateFrom != null) 'dateFrom': dateFrom,
        if (dateTo != null) 'dateTo': dateTo,
      },
      options: Options(receiveTimeout: ApiConstants.aiTimeout),
    );
    return response.data;
  }

  // AI Notifications
  Future<Map<String, dynamic>> getNotifications() async {
    final response = await _dio.get(ApiConstants.aiNotifications);
    return response.data;
  }

  // Mood Data
  Future<Map<String, dynamic>> getMoodData() async {
    final response = await _dio.get(ApiConstants.aiMoodData);
    return response.data;
  }

  // Color Memories
  Future<Map<String, dynamic>> getColorMemories(String hex) async {
    final response = await _dio.get(
      ApiConstants.aiColorMemories,
      queryParameters: {'hex': hex},
    );
    return response.data;
  }

  // Vibe Memories
  Future<Map<String, dynamic>> getVibeMemories(String vibe) async {
    final response = await _dio.get(
      ApiConstants.aiVibeMemories,
      queryParameters: {'vibe': vibe},
    );
    return response.data;
  }
}

/// SWR wrapper: returns cached data immediately, then fetches fresh data.
/// Callers get data instantly (if cached) and fresh data via callback.
class CachedApiService {
  final ApiService _api;
  final CacheService _cache;

  CachedApiService(this._api, this._cache);

  /// Generic SWR fetch. Returns cached data if available (may be stale),
  /// then always fetches fresh data from network.
  /// [onFresh] is called when network data arrives.
  Future<Map<String, dynamic>?> swr(
    String cacheKey,
    Future<Map<String, dynamic>> Function() fetcher, {
    void Function(Map<String, dynamic>)? onFresh,
    Duration ttl = const Duration(minutes: 10),
  }) async {
    // 1. Check cache
    final cached = await _cache.get(cacheKey);
    Map<String, dynamic>? staleData = cached?.data;

    // 2. If cache is fresh, return it and skip network
    if (cached != null && cached.isFresh) {
      // Still fire-and-forget a refresh for next time
      _refreshInBackground(cacheKey, fetcher, onFresh, ttl);
      return staleData;
    }

    // 3. Cache is stale or missing — try network
    try {
      final fresh = await fetcher();
      await _cache.put(cacheKey, fresh, ttl: ttl);
      onFresh?.call(fresh);
      return fresh;
    } catch (_) {
      // Network failed — return stale data if available
      return staleData;
    }
  }

  void _refreshInBackground(
    String key,
    Future<Map<String, dynamic>> Function() fetcher,
    void Function(Map<String, dynamic>)? onFresh,
    Duration ttl,
  ) {
    fetcher()
        .then((fresh) async {
          await _cache.put(key, fresh, ttl: ttl);
          onFresh?.call(fresh);
        })
        .catchError((_) {});
  }

  // ── Convenience methods for common screens ──────────────────

  Future<Map<String, dynamic>?> getDiscover({
    void Function(Map<String, dynamic>)? onFresh,
  }) {
    return swr('discover', _api.getDiscover, onFresh: onFresh);
  }

  Future<Map<String, dynamic>?> getMemoryMap({
    void Function(Map<String, dynamic>)? onFresh,
  }) {
    return swr('memory_map', _api.getMemoryMap, onFresh: onFresh);
  }

  Future<Map<String, dynamic>?> getMoodData({
    void Function(Map<String, dynamic>)? onFresh,
  }) {
    return swr('mood_data', _api.getMoodData, onFresh: onFresh);
  }

  Future<Map<String, dynamic>?> getNotifications({
    void Function(Map<String, dynamic>)? onFresh,
  }) {
    return swr(
      'notifications',
      _api.getNotifications,
      onFresh: onFresh,
      ttl: const Duration(minutes: 5),
    );
  }

  /// Memories list page cache for timeline (page-keyed).
  Future<List<dynamic>?> getMemories({
    int page = 1,
    int limit = 20,
    void Function(List<dynamic>)? onFresh,
  }) async {
    final key = 'memories_p${page}_l$limit';
    final cached = await _cache.get(key);

    if (cached != null && cached.isFresh) {
      // Background refresh
      _api
          .getMemories(page: page, limit: limit)
          .then((fresh) async {
            await _cache.put(key, {
              'list': fresh,
            }, ttl: const Duration(minutes: 5));
            onFresh?.call(fresh);
          })
          .catchError((_) {});
      return (cached.data['list'] as List<dynamic>?) ?? [];
    }

    try {
      final fresh = await _api.getMemories(page: page, limit: limit);
      await _cache.put(key, {'list': fresh}, ttl: const Duration(minutes: 5));
      return fresh;
    } catch (_) {
      if (cached != null) {
        return (cached.data['list'] as List<dynamic>?) ?? [];
      }
      rethrow;
    }
  }

  /// Invalidate specific keys after mutations.
  Future<void> invalidate(String key) => _cache.remove(key);

  /// Invalidate all timeline pages.
  Future<void> invalidateTimeline() async {
    for (int i = 1; i <= 20; i++) {
      await _cache.remove('memories_p${i}_l20');
    }
  }
}
