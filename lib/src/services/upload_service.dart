import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_compress/video_compress.dart';
import 'api_service.dart';

/// Upload status enum
enum UploadStatus { idle, compressing, uploading, processing, done, error }

/// Rich upload state with progress info
class UploadState {
  final UploadStatus status;
  final double progress; // 0.0 to 1.0
  final String? fileName;
  final String? thumbnailPath;
  final String? error;
  final bool isVideo;

  const UploadState({
    this.status = UploadStatus.idle,
    this.progress = 0,
    this.fileName,
    this.thumbnailPath,
    this.error,
    this.isVideo = false,
  });

  String get statusText {
    switch (status) {
      case UploadStatus.idle:
        return '';
      case UploadStatus.compressing:
        return isVideo ? 'Compressing video…' : 'Optimizing…';
      case UploadStatus.uploading:
        return 'Uploading${progress > 0 ? ' ${(progress * 100).toInt()}%' : '…'}';
      case UploadStatus.processing:
        return 'Processing…';
      case UploadStatus.done:
        return 'Saved!';
      case UploadStatus.error:
        return error ?? 'Upload failed';
    }
  }

  UploadState copyWith({
    UploadStatus? status,
    double? progress,
    String? fileName,
    String? thumbnailPath,
    String? error,
    bool? isVideo,
  }) {
    return UploadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      fileName: fileName ?? this.fileName,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      error: error ?? this.error,
      isVideo: isVideo ?? this.isVideo,
    );
  }
}

final uploadServiceProvider = Provider<UploadService>((ref) {
  return UploadService(ref.read(apiServiceProvider));
});

/// Tracks active upload count for optional UI indicators
final activeUploadCountProvider = StateProvider<int>((ref) => 0);

/// Rich upload state provider
final uploadStateProvider = StateProvider<UploadState>(
  (ref) => const UploadState(),
);

class UploadService {
  final ApiService _api;
  UploadService(this._api);

  /// Upload a file in the background with compression and progress.
  void uploadInBackground({
    required ProviderContainer container,
    required File file,
    required String type,
    double? latitude,
    double? longitude,
    String? locationName,
    void Function(Map<String, dynamic> result)? onSuccess,
    void Function(Object error)? onError,
  }) {
    container.read(activeUploadCountProvider.notifier).state++;
    container.read(uploadStateProvider.notifier).state = UploadState(
      status: UploadStatus.compressing,
      fileName: file.path.split('/').last,
      isVideo: type == 'video',
    );

    _compressAndUpload(
          container,
          file,
          type,
          latitude: latitude,
          longitude: longitude,
          locationName: locationName,
        )
        .then((result) {
          container.read(activeUploadCountProvider.notifier).state--;
          container.read(uploadStateProvider.notifier).state =
              const UploadState(status: UploadStatus.done);
          // Auto-clear after 2 seconds
          Future.delayed(const Duration(seconds: 2), () {
            final current = container.read(uploadStateProvider);
            if (current.status == UploadStatus.done) {
              container.read(uploadStateProvider.notifier).state =
                  const UploadState();
            }
          });
          onSuccess?.call(result);
        })
        .catchError((Object e) {
          container.read(activeUploadCountProvider.notifier).state--;
          container.read(uploadStateProvider.notifier).state = UploadState(
            status: UploadStatus.error,
            error: 'Upload failed',
            isVideo: type == 'video',
          );
          // Auto-clear error after 3 seconds
          Future.delayed(const Duration(seconds: 3), () {
            final current = container.read(uploadStateProvider);
            if (current.status == UploadStatus.error) {
              container.read(uploadStateProvider.notifier).state =
                  const UploadState();
            }
          });
          debugPrint('Background upload failed: $e');
          onError?.call(e);
        });
  }

  Future<Map<String, dynamic>> _compressAndUpload(
    ProviderContainer container,
    File file,
    String type, {
    double? latitude,
    double? longitude,
    String? locationName,
  }) async {
    File uploadFile = file;

    if (type == 'video') {
      // Compress video
      try {
        container.read(uploadStateProvider.notifier).state = UploadState(
          status: UploadStatus.compressing,
          isVideo: true,
          fileName: file.path.split('/').last,
        );

        final info = await VideoCompress.compressVideo(
          file.path,
          quality: VideoQuality.MediumQuality,
          deleteOrigin: false,
          includeAudio: true,
        );

        if (info != null && info.file != null) {
          uploadFile = info.file!;
          final origSize = await file.length();
          final compSize = await uploadFile.length();
          debugPrint(
            'Video compressed: ${(origSize / 1024 / 1024).toStringAsFixed(1)}MB → ${(compSize / 1024 / 1024).toStringAsFixed(1)}MB',
          );
        }
      } catch (e) {
        debugPrint('Video compression failed, uploading raw: $e');
      }
    }

    // Update to uploading state
    container.read(uploadStateProvider.notifier).state = UploadState(
      status: UploadStatus.uploading,
      progress: 0,
      isVideo: type == 'video',
      fileName: file.path.split('/').last,
    );

    final result = await _api.createMemory(
      files: [uploadFile],
      types: [type],
      latitude: latitude,
      longitude: longitude,
      locationName: locationName,
      onProgress: (sent, total) {
        if (total > 0) {
          container.read(uploadStateProvider.notifier).state = UploadState(
            status: UploadStatus.uploading,
            progress: sent / total,
            isVideo: type == 'video',
            fileName: file.path.split('/').last,
          );
        }
      },
    );

    // Processing (AI caption etc.)
    container.read(uploadStateProvider.notifier).state = UploadState(
      status: UploadStatus.processing,
      isVideo: type == 'video',
      fileName: file.path.split('/').last,
    );

    return result;
  }
}
