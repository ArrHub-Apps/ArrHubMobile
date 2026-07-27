import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Trusts the desktop's self-signed remote-access certificate by pinning its SHA-256
/// fingerprint, so remote HTTPS works without a public CA and can't be MITM'd.
///
/// Installed as [HttpOverrides.global], so it covers every dart:io HTTP client —
/// including the ones inside `http` and `cached_network_image` (posters). The override's
/// `badCertificateCallback` only fires for certs that fail normal CA validation, so
/// public sites (e.g. TMDB) are unaffected: a self-signed remote cert is accepted only
/// when its fingerprint is one we've been paired with.
class CertPinning {
  static final Set<String> _fingerprints = {};

  /// Registers a fingerprint (from a pairing bundle) as trusted. No-op for empty values.
  static void add(String? fingerprint) {
    if (fingerprint != null && fingerprint.isNotEmpty) {
      _fingerprints.add(_canon(fingerprint));
    }
  }

  static bool _trusts(String fingerprint) => _fingerprints.contains(_canon(fingerprint));

  static String _canon(String fp) => fp.replaceAll(':', '').toLowerCase();

  static void install() {
    HttpOverrides.global = _PinningHttpOverrides();
  }
}

class _PinningHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) {
        // Dev machines re-sign HTTPS (corporate AV), which would otherwise break TMDB
        // from the emulator — accept everything in debug, as the app did before.
        if (kDebugMode) return true;
        final fingerprint = sha256.convert(cert.der).toString();
        return CertPinning._trusts(fingerprint);
      };
  }
}
