import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_service.dart';

/// Manages background uploads so the user isn't blocked.
/// Queues files, uploads them silently, and reports results via callbacks.

final uploadServiceProvider = Provider<UploadService>((ref) {
  return UploadService(ref.read(apiServiceProvider));
});

/// Tracks active upload count for optional UI indicators
final activeUploadCountProvider = StateProvider<int>((ref) => 0);

class UploadService {
  final ApiService _api;
  UploadService(this._api);

  /// Upload a file in the background. Returns immediately.
  /// [onSuccess] is called with the parsed result when done.
  /// [onError] is called if the upload fails.
  void uploadInBackground({
    required ProviderContainer container,
    required File file,
    required String type,
    void Function(Map<String, dynamic> result)? onSuccess,
    void Function(Object error)? onError,
  }) {
    // Increment active count
    container.read(activeUploadCountProvider.notifier).state++;

    _doUpload(file, type)
        .then((result) {
          container.read(activeUploadCountProvider.notifier).state--;
          onSuccess?.call(result);
        })
        .catchError((Object e) {
          container.read(activeUploadCountProvider.notifier).state--;
          debugPrint('Background upload failed: $e');
          onError?.call(e);
        });
  }

  Future<Map<String, dynamic>> _doUpload(File file, String type) async {
    return _api.createMemory(files: [file], types: [type]);
  }
}
