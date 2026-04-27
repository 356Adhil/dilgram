import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/api_constants.dart';

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

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
    void Function(int, int)? onProgress,
  }) async {
    final formData = FormData();

    if (title != null) formData.fields.add(MapEntry('title', title));
    if (description != null) {
      formData.fields.add(MapEntry('description', description));
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
}
