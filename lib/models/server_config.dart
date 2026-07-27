import 'dart:convert';

enum ServerType { radarr, sonarr }

/// Which URL the app is currently talking to. 'lan' is the home-network address;
/// 'remote' is the internet-reachable HTTPS address served by the desktop's TLS proxy.
enum HostChoice { lan, remote }

class ServerConfig {
  final ServerType type;

  /// Home-network URL (plain HTTP). The primary/default address.
  final String baseUrl;
  final String apiKey;

  /// Internet-reachable HTTPS URL from a pairing bundle, when the host has remote
  /// access set up. Empty when there's only a LAN address.
  final String remoteUrl;

  /// SHA-256 fingerprint (lowercase hex, no separators) of the remote server's
  /// self-signed cert, pinned to trust the connection. Empty when there's no remote URL.
  final String certFingerprint;

  /// Which address to use right now. Flips automatically based on reachability.
  final HostChoice activeHost;

  const ServerConfig({
    required this.type,
    required this.baseUrl,
    required this.apiKey,
    this.remoteUrl = '',
    this.certFingerprint = '',
    this.activeHost = HostChoice.lan,
  });

  bool get isConfigured => baseUrl.isNotEmpty && apiKey.isNotEmpty;
  bool get hasRemote => remoteUrl.isNotEmpty;

  static String _normalize(String url) {
    var u = url.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'http://$u';
    }
    return u;
  }

  /// Normalized LAN base URL without a trailing slash.
  String get normalizedUrl => _normalize(baseUrl);

  /// Normalized remote URL, or '' if there isn't one.
  String get normalizedRemoteUrl => remoteUrl.isEmpty ? '' : _normalize(remoteUrl);

  /// The URL the API client and image loaders should actually use, honouring the
  /// active-host choice (falls back to LAN if remote is selected but not configured).
  String get activeUrl =>
      activeHost == HostChoice.remote && hasRemote ? normalizedRemoteUrl : normalizedUrl;

  ServerConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? remoteUrl,
    String? certFingerprint,
    HostChoice? activeHost,
  }) =>
      ServerConfig(
        type: type,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        remoteUrl: remoteUrl ?? this.remoteUrl,
        certFingerprint: certFingerprint ?? this.certFingerprint,
        activeHost: activeHost ?? this.activeHost,
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'remoteUrl': remoteUrl,
        'certFingerprint': certFingerprint,
        'activeHost': activeHost.name,
      };

  factory ServerConfig.fromJson(Map<String, dynamic> json) => ServerConfig(
        type: ServerType.values.byName(json['type'] as String),
        baseUrl: json['baseUrl'] as String? ?? '',
        apiKey: json['apiKey'] as String? ?? '',
        remoteUrl: json['remoteUrl'] as String? ?? '',
        certFingerprint: json['certFingerprint'] as String? ?? '',
        activeHost: HostChoice.values.firstWhere(
          (h) => h.name == (json['activeHost'] as String?),
          orElse: () => HostChoice.lan,
        ),
      );

  String encode() => jsonEncode(toJson());

  static ServerConfig? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return ServerConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}
