import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/server_config.dart';

/// The connection details the desktop hands out when a pairing code is claimed.
class PairingBundle {
  final String radarrUrl;
  final String radarrApiKey;
  final String sonarrUrl;
  final String sonarrApiKey;

  /// Internet-reachable HTTPS URLs + pinned cert fingerprint. Present only when the
  /// host has remote access enabled and tested; empty otherwise (LAN-only pairing).
  final String radarrRemoteUrl;
  final String sonarrRemoteUrl;
  final String certFingerprint;

  /// The host's TMDB API key, shared so this phone's Discover tab works immediately.
  /// Empty when the host hasn't configured one.
  final String tmdbApiKey;

  const PairingBundle({
    required this.radarrUrl,
    required this.radarrApiKey,
    required this.sonarrUrl,
    required this.sonarrApiKey,
    this.radarrRemoteUrl = '',
    this.sonarrRemoteUrl = '',
    this.certFingerprint = '',
    this.tmdbApiKey = '',
  });

  factory PairingBundle.fromJson(Map<String, dynamic> json) => PairingBundle(
        radarrUrl: json['radarrUrl'] as String? ?? '',
        radarrApiKey: json['radarrApiKey'] as String? ?? '',
        sonarrUrl: json['sonarrUrl'] as String? ?? '',
        sonarrApiKey: json['sonarrApiKey'] as String? ?? '',
        radarrRemoteUrl: json['radarrRemoteUrl'] as String? ?? '',
        sonarrRemoteUrl: json['sonarrRemoteUrl'] as String? ?? '',
        certFingerprint: json['certFingerprint'] as String? ?? '',
        tmdbApiKey: json['tmdbApiKey'] as String? ?? '',
      );

  /// Builds a [ServerConfig] for the given service. The LAN URL is primary; the app
  /// probes and falls back to remote automatically when away from home.
  ServerConfig configFor(ServerType type) => ServerConfig(
        type: type,
        baseUrl: type == ServerType.radarr ? radarrUrl : sonarrUrl,
        apiKey: type == ServerType.radarr ? radarrApiKey : sonarrApiKey,
        remoteUrl: type == ServerType.radarr ? radarrRemoteUrl : sonarrRemoteUrl,
        certFingerprint: certFingerprint,
        activeHost: HostChoice.lan,
      );
}

class PairingException implements Exception {
  final String message;
  PairingException(this.message);
  @override
  String toString() => message;
}

/// Claims a pairing code against a desktop host's LAN pairing server and returns the
/// resulting bundle. Surfaces the server's own error messages (invalid/expired code,
/// services not ready) verbatim.
class PairingService {
  static Future<PairingBundle> claim(String host, int port, String code) async {
    final Uri uri;
    try {
      uri = Uri.parse('http://$host:$port/pair/claim');
    } catch (_) {
      throw PairingException('That QR code / host looks malformed.');
    }

    http.Response resp;
    try {
      resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'code': code}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      throw PairingException(
        "Couldn't reach the desktop at $host:$port — make sure you're on the same "
        'Wi-Fi and ArrHub is running on the PC.',
      );
    }

    if (resp.statusCode != 200) {
      String detail = '';
      try {
        detail = (jsonDecode(resp.body) as Map<String, dynamic>)['error'] as String? ?? '';
      } catch (_) {}
      throw PairingException(
          detail.isNotEmpty ? detail : 'Pairing failed (HTTP ${resp.statusCode}).');
    }

    try {
      return PairingBundle.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    } catch (_) {
      throw PairingException('The desktop sent an unexpected response.');
    }
  }
}
