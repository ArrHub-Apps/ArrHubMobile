import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// In-app self-update against this app's own PUBLIC GitHub Releases.
///
/// The app is sideloaded (not on the Play Store), so it updates itself: check the
/// latest release of ArrHub-Apps/ArrHubMobile, and if it's newer than the running
/// build, download the APK and hand it to Android's package installer. Reading those
/// releases anonymously works because the repo is public (mirrors the desktop app's
/// model — DAN-47). Same notify-then-download UX (never silently downloads/installs).
///
/// Android only: iOS can't sideload an update this way, so [checkForUpdate] returns
/// null on non-Android platforms and callers hide the update UI.
class UpdateService {
  /// This repo's own public Releases, read unauthenticated (a token baked into a
  /// distributed APK would be extractable anyway).
  static const _owner = 'ArrHub-Apps';
  static const _repo = 'ArrHubMobile';

  static Uri get _latestReleaseUrl =>
      Uri.parse('https://api.github.com/repos/$_owner/$_repo/releases/latest');

  /// Returns details of a newer release if one exists, else null (already current,
  /// no release yet, offline, or not on Android).
  static Future<AppUpdate?> checkForUpdate() async {
    if (!Platform.isAndroid) return null;

    final info = await PackageInfo.fromPlatform();
    final current = _Version.parse(info.version);

    final resp = await http.get(
      _latestReleaseUrl,
      // GitHub's REST API wants a UA and serves the stable v3 JSON with this Accept.
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'ArrHub-Mobile',
      },
    );
    // 404 = no published release yet; anything non-200 is treated as "no update".
    if (resp.statusCode != 200) return null;

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    if (json['draft'] == true || json['prerelease'] == true) return null;

    final tag = (json['tag_name'] as String?) ?? '';
    final latest = _Version.parse(tag);
    if (latest == null || current == null || !latest.isNewerThan(current)) {
      return null;
    }

    // Find the .apk asset to download.
    final assets = (json['assets'] as List<dynamic>? ?? []);
    final apk = assets.cast<Map<String, dynamic>>().firstWhere(
          (a) => (a['name'] as String? ?? '').toLowerCase().endsWith('.apk'),
          orElse: () => const {},
        );
    final apkUrl = apk['browser_download_url'] as String?;
    if (apkUrl == null) return null;

    return AppUpdate(
      version: latest.toString(),
      currentVersion: current.toString(),
      notes: (json['body'] as String?)?.trim() ?? '',
      apkUrl: apkUrl,
      apkSize: (apk['size'] as num?)?.toInt() ?? 0,
    );
  }

  /// Downloads [update]'s APK, reporting progress as a 0.0–1.0 fraction (or null
  /// when the total size is unknown), and returns the local file path. Streams to
  /// disk so a large APK never has to sit fully in memory.
  static Future<String> downloadApk(
    AppUpdate update, {
    void Function(double? progress)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/ArrHub-${update.version}.apk');

    final client = http.Client();
    try {
      final resp =
          await client.send(http.Request('GET', Uri.parse(update.apkUrl)));
      if (resp.statusCode != 200) {
        throw Exception('Download failed (HTTP ${resp.statusCode})');
      }
      final total = resp.contentLength ?? update.apkSize;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in resp.stream) {
          received += chunk.length;
          sink.add(chunk);
          onProgress?.call(total > 0 ? received / total : null);
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }
    return file.path;
  }

  /// Hands the downloaded APK to Android's package installer. The user still
  /// confirms the install in the system UI; this just opens it. Requires the
  /// REQUEST_INSTALL_PACKAGES permission (declared in AndroidManifest.xml).
  static Future<void> installApk(String path) async {
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      throw Exception(result.message);
    }
  }
}

/// A newer release the user can choose to install.
class AppUpdate {
  final String version;
  final String currentVersion;
  final String notes;
  final String apkUrl;
  final int apkSize;

  const AppUpdate({
    required this.version,
    required this.currentVersion,
    required this.notes,
    required this.apkUrl,
    required this.apkSize,
  });
}

/// Minimal semver (major.minor.patch) parse + compare — enough for the app's
/// `x.y.z` versions and tolerant of a leading `v` on release tags. Anything it
/// can't parse yields null, which callers treat as "don't offer an update".
class _Version implements Comparable<_Version> {
  final int major;
  final int minor;
  final int patch;

  const _Version(this.major, this.minor, this.patch);

  static _Version? parse(String raw) {
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    // Drop any build/prerelease suffix (0.1.0+3, 0.1.0-beta) before splitting.
    s = s.split(RegExp(r'[-+]')).first;
    final parts = s.split('.');
    if (parts.isEmpty) return null;
    final nums = parts.map(int.tryParse).toList();
    if (nums.any((n) => n == null)) return null;
    return _Version(
      nums[0]!,
      nums.length > 1 ? nums[1]! : 0,
      nums.length > 2 ? nums[2]! : 0,
    );
  }

  bool isNewerThan(_Version other) => compareTo(other) > 0;

  @override
  int compareTo(_Version o) {
    if (major != o.major) return major - o.major;
    if (minor != o.minor) return minor - o.minor;
    return patch - o.patch;
  }

  @override
  String toString() => '$major.$minor.$patch';
}
