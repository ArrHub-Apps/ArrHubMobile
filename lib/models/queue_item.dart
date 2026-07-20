/// One entry in the Radarr/Sonarr download queue.
class QueueItem {
  final int id;
  final String mediaTitle; // movie or series title
  final String? episodeLabel; // "S01E05", Sonarr only
  final String releaseTitle;
  final String status;
  final String trackedDownloadState;
  final String? errorMessage;
  final double size;
  final double sizeleft;
  final String? timeleft;
  final String protocol;
  final String? posterUrl;

  const QueueItem({
    required this.id,
    required this.mediaTitle,
    required this.episodeLabel,
    required this.releaseTitle,
    required this.status,
    required this.trackedDownloadState,
    required this.errorMessage,
    required this.size,
    required this.sizeleft,
    required this.timeleft,
    required this.protocol,
    required this.posterUrl,
  });

  double get progress =>
      size > 0 ? ((size - sizeleft) / size).clamp(0.0, 1.0) : 0;

  String get sizeLabel {
    String fmt(double b) {
      final gb = b / (1024 * 1024 * 1024);
      if (gb >= 1) return '${gb.toStringAsFixed(1)} GB';
      return '${(b / (1024 * 1024)).toStringAsFixed(0)} MB';
    }

    return '${fmt(size - sizeleft)} / ${fmt(size)}';
  }

  /// Human status, folding the tracked-download import states in.
  String get statusLabel {
    if (trackedDownloadState == 'importPending' ||
        trackedDownloadState == 'importing') {
      return 'Importing';
    }
    return switch (status) {
      'downloading' => 'Downloading',
      'paused' => 'Paused',
      'queued' || 'delay' => 'Queued',
      'completed' => 'Completed',
      'failed' => 'Failed',
      'warning' => 'Warning',
      _ => status,
    };
  }

  bool get hasProblem =>
      status == 'failed' || status == 'warning' || errorMessage != null;

  factory QueueItem.fromJson(
    Map<String, dynamic> json,
    bool isRadarr,
    String baseUrl,
    String apiKey,
  ) {
    final media = (isRadarr ? json['movie'] : json['series'])
        as Map<String, dynamic>?;
    final mediaId = isRadarr ? json['movieId'] : json['seriesId'];
    final episode = json['episode'] as Map<String, dynamic>?;
    String? episodeLabel;
    if (episode != null) {
      final s = episode['seasonNumber'] as int? ?? 0;
      final e = episode['episodeNumber'] as int? ?? 0;
      episodeLabel =
          'S${s.toString().padLeft(2, "0")}E${e.toString().padLeft(2, "0")}';
    }
    return QueueItem(
      id: json['id'] as int,
      mediaTitle: media?['title'] as String? ?? 'Unknown',
      episodeLabel: episodeLabel,
      releaseTitle: json['title'] as String? ?? '',
      status: json['status'] as String? ?? '',
      trackedDownloadState: json['trackedDownloadState'] as String? ?? '',
      errorMessage: json['errorMessage'] as String?,
      size: (json['size'] as num? ?? 0).toDouble(),
      sizeleft: (json['sizeleft'] as num? ?? 0).toDouble(),
      timeleft: json['timeleft'] as String?,
      protocol: json['protocol'] as String? ?? '',
      posterUrl: mediaId == null
          ? null
          : '$baseUrl/api/v3/mediacover/$mediaId/poster.jpg?apikey=$apiKey',
    );
  }
}
