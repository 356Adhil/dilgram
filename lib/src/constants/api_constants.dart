import 'dart:io' show Platform;

class ApiConstants {
  ApiConstants._();

  // Base URL - auto-detect for Android emulator vs iOS simulator vs real device
  static String get baseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) return envUrl;

    // Android emulator uses 10.0.2.2 to reach host machine's localhost
    // iOS simulator can use localhost directly
    try {
      if (Platform.isAndroid) {
        return 'http://10.0.2.2:3000/api';
      }
    } catch (_) {}
    return 'http://localhost:3000/api';
  }

  // Auth
  static const String setupPin = '/auth/setup-pin';
  static const String verifyPin = '/auth/verify-pin';

  // Memories
  static const String memories = '/memories';
  static String memory(String id) => '/memories/$id';
  static String memoryMedia(String id) => '/memories/$id/media';
  static String deleteMedia(String memoryId, String mediaId) =>
      '/memories/$memoryId/media/$mediaId';
  static const String memoriesStats = '/memories/stats';

  // Timeouts
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 60);
  static const Duration uploadTimeout = Duration(minutes: 5);
}
