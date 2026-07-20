import 'dart:convert';

enum ServerType { radarr, sonarr }

class ServerConfig {
  final ServerType type;
  final String baseUrl;
  final String apiKey;

  const ServerConfig({
    required this.type,
    required this.baseUrl,
    required this.apiKey,
  });

  bool get isConfigured => baseUrl.isNotEmpty && apiKey.isNotEmpty;

  /// Normalized base URL without a trailing slash.
  String get normalizedUrl {
    var url = baseUrl.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    return url;
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
      };

  factory ServerConfig.fromJson(Map<String, dynamic> json) => ServerConfig(
        type: ServerType.values.byName(json['type'] as String),
        baseUrl: json['baseUrl'] as String? ?? '',
        apiKey: json['apiKey'] as String? ?? '',
      );

  String encode() => jsonEncode(toJson());

  static ServerConfig? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return ServerConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}
