class ApiConstants {
  ApiConstants._();

  // Base URL
  static const String baseUrl = 'https://dilgram.onrender.com/api';

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
