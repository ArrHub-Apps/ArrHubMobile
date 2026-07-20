/// One Sonarr episode. hasFile/monitored are mutable so the episode
/// browser can update rows optimistically after API calls.
class Episode {
  final int id;
  final int seasonNumber;
  final int episodeNumber;
  final String title;
  final DateTime? airDate;
  bool hasFile;
  bool monitored;

  Episode({
    required this.id,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.title,
    required this.airDate,
    required this.hasFile,
    required this.monitored,
  });

  String get code =>
      'S${seasonNumber.toString().padLeft(2, "0")}E${episodeNumber.toString().padLeft(2, "0")}';

  bool get aired =>
      airDate != null && airDate!.isBefore(DateTime.now().toUtc());

  String get airDateLabel {
    final d = airDate?.toLocal();
    if (d == null) return 'No air date';
    return '${d.day.toString().padLeft(2, "0")}/${d.month.toString().padLeft(2, "0")}/${d.year}';
  }

  factory Episode.fromJson(Map<String, dynamic> json) => Episode(
        id: json['id'] as int,
        seasonNumber: json['seasonNumber'] as int? ?? 0,
        episodeNumber: json['episodeNumber'] as int? ?? 0,
        title: json['title'] as String? ?? 'TBA',
        airDate: DateTime.tryParse(json['airDateUtc'] as String? ?? ''),
        hasFile: json['hasFile'] as bool? ?? false,
        monitored: json['monitored'] as bool? ?? false,
      );
}
