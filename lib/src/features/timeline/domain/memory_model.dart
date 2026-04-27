class MemoryLocation {
  final double lat;
  final double lng;
  final String? name;

  const MemoryLocation({required this.lat, required this.lng, this.name});

  factory MemoryLocation.fromJson(Map<String, dynamic> json) {
    return MemoryLocation(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      name: json['name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    if (name != null) 'name': name,
  };
}

class Memory {
  final String id;
  final String? title;
  final String? description;
  final List<MediaItem> mediaItems;
  final List<String> tags;
  final String? mood;
  final bool isFavorite;
  final MemoryLocation? location;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Memory({
    required this.id,
    this.title,
    this.description,
    required this.mediaItems,
    this.tags = const [],
    this.mood,
    this.isFavorite = false,
    this.location,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Memory.fromJson(Map<String, dynamic> json) {
    return Memory(
      id: json['_id'] as String,
      title: json['title'] as String?,
      description: json['description'] as String?,
      mediaItems:
          (json['mediaItems'] as List<dynamic>?)
              ?.map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          [],
      mood: json['mood'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      location: json['location'] != null && json['location']['lat'] != null
          ? MemoryLocation.fromJson(json['location'] as Map<String, dynamic>)
          : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    '_id': id,
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    'mediaItems': mediaItems.map((e) => e.toJson()).toList(),
    'tags': tags,
    if (mood != null) 'mood': mood,
    'isFavorite': isFavorite,
    if (location != null) 'location': location!.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  Memory copyWith({
    String? id,
    String? title,
    String? description,
    List<MediaItem>? mediaItems,
    List<String>? tags,
    String? mood,
    bool? isFavorite,
    MemoryLocation? location,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Memory(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      mediaItems: mediaItems ?? this.mediaItems,
      tags: tags ?? this.tags,
      mood: mood ?? this.mood,
      isFavorite: isFavorite ?? this.isFavorite,
      location: location ?? this.location,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

enum MediaType { photo, video }

class MediaItem {
  final String id;
  final MediaType type;
  final String url;
  final String publicId;
  final String? thumbnailUrl;
  final int? width;
  final int? height;
  final double? duration;
  final int? size;
  final String? mimeType;
  final DateTime uploadedAt;

  const MediaItem({
    required this.id,
    required this.type,
    required this.url,
    required this.publicId,
    this.thumbnailUrl,
    this.width,
    this.height,
    this.duration,
    this.size,
    this.mimeType,
    required this.uploadedAt,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: json['_id'] as String? ?? json['id'] as String,
      type: json['type'] == 'video' ? MediaType.video : MediaType.photo,
      url: json['cloudinaryUrl'] as String? ?? json['url'] as String,
      publicId:
          json['cloudinaryPublicId'] as String? ??
          json['publicId'] as String? ??
          '',
      thumbnailUrl: json['thumbnailUrl'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      duration: (json['duration'] as num?)?.toDouble(),
      size: json['size'] as int?,
      mimeType: json['mimeType'] as String?,
      uploadedAt: DateTime.parse(json['uploadedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    '_id': id,
    'type': type == MediaType.video ? 'video' : 'photo',
    'cloudinaryUrl': url,
    'cloudinaryPublicId': publicId,
    if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (duration != null) 'duration': duration,
    if (size != null) 'size': size,
    if (mimeType != null) 'mimeType': mimeType,
    'uploadedAt': uploadedAt.toIso8601String(),
  };

  bool get isVideo => type == MediaType.video;
  bool get isPhoto => type == MediaType.photo;

  String get formattedDuration {
    if (duration == null) return '';
    final d = Duration(milliseconds: (duration! * 1000).toInt());
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class MemoryStats {
  final int totalMemories;
  final int totalPhotos;
  final int totalVideos;
  final int totalSizeBytes;

  const MemoryStats({
    required this.totalMemories,
    required this.totalPhotos,
    required this.totalVideos,
    required this.totalSizeBytes,
  });

  factory MemoryStats.fromJson(Map<String, dynamic> json) {
    return MemoryStats(
      totalMemories: json['totalMemories'] as int? ?? 0,
      totalPhotos: json['totalPhotos'] as int? ?? 0,
      totalVideos: json['totalVideos'] as int? ?? 0,
      totalSizeBytes: json['totalSizeBytes'] as int? ?? 0,
    );
  }

  String get formattedSize {
    if (totalSizeBytes < 1024) return '$totalSizeBytes B';
    if (totalSizeBytes < 1024 * 1024) {
      return '${(totalSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (totalSizeBytes < 1024 * 1024 * 1024) {
      return '${(totalSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(totalSizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
