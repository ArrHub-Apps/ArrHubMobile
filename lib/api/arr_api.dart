import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/episode.dart';
import '../models/media_item.dart';
import '../models/queue_item.dart';
import '../models/release.dart';
import '../models/server_config.dart';

class ArrApiException implements Exception {
  final String message;
  final int? statusCode;
  ArrApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

/// Client for the Radarr/Sonarr v3 HTTP API. The two services share the
/// same API shape; the differences (endpoint names, add payloads) are
/// handled per [ServerType].
class ArrApi {
  final ServerConfig config;
  final http.Client _client;

  ArrApi(this.config, {http.Client? client})
    : _client = client ?? http.Client();

  bool get _isRadarr => config.type == ServerType.radarr;

  String get _mediaPath => _isRadarr ? 'movie' : 'series';

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse(
    '${config.activeUrl}/api/v3/$path',
  ).replace(queryParameters: query);

  Map<String, String> get _headers => {
    'X-Api-Key': config.apiKey,
    'Content-Type': 'application/json',
  };

  // Generous default: the server can be slow to respond while the
  // download client saturates the host's disk/network.
  Future<dynamic> _get(
    String path, [
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 60),
  ]) async {
    final resp = await _client
        .get(_uri(path, query), headers: _headers)
        .timeout(timeout);
    _check(resp);
    return jsonDecode(resp.body);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final resp = await _client
        .post(_uri(path), headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));
    _check(resp);
    return jsonDecode(resp.body);
  }

  Future<void> _put(String path, Map<String, dynamic> body) async {
    final resp = await _client
        .put(_uri(path), headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));
    _check(resp);
  }

  void _check(http.Response resp) {
    if (resp.statusCode == 401) {
      throw ArrApiException('Invalid API key', 401);
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      String detail = '';
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is List && decoded.isNotEmpty) {
          detail = decoded.first['errorMessage'] as String? ?? '';
        } else if (decoded is Map) {
          detail = decoded['message'] as String? ?? '';
        }
      } catch (_) {}
      throw ArrApiException(
        detail.isNotEmpty ? detail : 'Server error (HTTP ${resp.statusCode})',
        resp.statusCode,
      );
    }
  }

  MediaItem _toItem(Map<String, dynamic> json) => _isRadarr
      ? MediaItem.movie(json, config.activeUrl, config.apiKey)
      : MediaItem.series(json, config.activeUrl, config.apiKey);

  /// Verifies connectivity and credentials; returns the server version.
  Future<String> testConnection() async {
    final status = await _get('system/status') as Map<String, dynamic>;
    return status['version'] as String? ?? 'unknown';
  }

  /// Fast, quiet reachability check for the active host — true if the server answers
  /// on system/status within [timeout]. Used to decide between LAN and remote URLs.
  Future<bool> probe([Duration timeout = const Duration(seconds: 4)]) async {
    try {
      final resp = await _client
          .get(_uri('system/status'), headers: _headers)
          .timeout(timeout);
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<List<MediaItem>> getLibrary() async {
    final list = await _get(_mediaPath) as List<dynamic>;
    return list.map((e) => _toItem(e as Map<String, dynamic>)).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  Future<List<MediaItem>> lookup(String term) async {
    final list =
        await _get('$_mediaPath/lookup', {'term': term}) as List<dynamic>;
    return list.map((e) => _toItem(e as Map<String, dynamic>)).toList();
  }

  /// Exact lookup by TMDB id (both Radarr and Sonarr v4 support the
  /// tmdb: search prefix). Returns null if the server finds no match.
  Future<MediaItem?> lookupByTmdbId(int tmdbId) async {
    final results = await lookup('tmdb:$tmdbId');
    return results.isEmpty ? null : results.first;
  }

  Future<List<QualityProfile>> getQualityProfiles() async {
    final list = await _get('qualityprofile') as List<dynamic>;
    return list
        .map((e) => QualityProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<RootFolder>> getRootFolders() async {
    final list = await _get('rootfolder') as List<dynamic>;
    return list
        .map((e) => RootFolder.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Recent completed imports (download finished + moved into library),
  /// newest first, as (date, human title) pairs.
  Future<List<(DateTime, String)>> recentImports() async {
    final data =
        await _get('history', {
              'page': '1',
              'pageSize': '20',
              'sortKey': 'date',
              'sortDirection': 'descending',
              'eventType': '3', // downloadFolderImported
              if (_isRadarr) 'includeMovie': 'true',
              if (!_isRadarr) ...{
                'includeSeries': 'true',
                'includeEpisode': 'true',
              },
            })
            as Map<String, dynamic>;
    final records = data['records'] as List<dynamic>? ?? [];
    final imports = <(DateTime, String)>[];
    for (final r in records) {
      final record = r as Map<String, dynamic>;
      final date = DateTime.tryParse(record['date'] as String? ?? '');
      if (date == null) continue;
      String title;
      if (_isRadarr) {
        title =
            (record['movie'] as Map<String, dynamic>?)?['title'] as String? ??
            record['sourceTitle'] as String? ??
            'Unknown movie';
      } else {
        final series =
            (record['series'] as Map<String, dynamic>?)?['title'] as String? ??
            'Unknown series';
        final episode = record['episode'] as Map<String, dynamic>?;
        if (episode != null) {
          final s = episode['seasonNumber'] as int? ?? 0;
          final e = episode['episodeNumber'] as int? ?? 0;
          title =
              '$series S${s.toString().padLeft(2, "0")}E${e.toString().padLeft(2, "0")}';
        } else {
          title = series;
        }
      }
      imports.add((date, title));
    }
    return imports;
  }

  /// Full queue with media details for the Queue tab.
  Future<List<QueueItem>> getQueue() async {
    final query = {
      'pageSize': '1000',
      if (_isRadarr) 'includeMovie': 'true',
      if (!_isRadarr) ...{'includeSeries': 'true', 'includeEpisode': 'true'},
    };
    final data = await _get('queue', query) as Map<String, dynamic>;
    final records = data['records'] as List<dynamic>? ?? [];
    return records
        .map(
          (r) => QueueItem.fromJson(
            r as Map<String, dynamic>,
            _isRadarr,
            config.activeUrl,
            config.apiKey,
          ),
        )
        .toList();
  }

  /// Removes a queue entry. [removeFromClient] also deletes the download
  /// in the download client; [blocklist] prevents regrabbing this release.
  Future<void> deleteQueueItem(
    int id, {
    bool removeFromClient = true,
    bool blocklist = false,
  }) async {
    final resp = await _client
        .delete(
          _uri('queue/$id', {
            'removeFromClient': '$removeFromClient',
            'blocklist': '$blocklist',
          }),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 60));
    _check(resp);
  }

  /// Ids of movies/series with something in the download queue.
  Future<Set<int>> getQueueIds() async {
    final data =
        await _get('queue', {'pageSize': '1000'}) as Map<String, dynamic>;
    final records = data['records'] as List<dynamic>? ?? [];
    final idKey = _isRadarr ? 'movieId' : 'seriesId';
    return records
        .map((r) => (r as Map<String, dynamic>)[idKey] as int?)
        .whereType<int>()
        .toSet();
  }

  Future<List<DiskSpace>> getDiskSpace() async {
    final list = await _get('diskspace') as List<dynamic>;
    return list
        .map((e) => DiskSpace.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Disk space entries for only the drives/mounts hosting this server's
  /// root folders (longest-prefix match, so mount points win over /).
  Future<List<DiskSpace>> getRootFolderDiskSpace() async {
    final folders = await getRootFolders();
    final disks = await getDiskSpace();
    final matched = <String, DiskSpace>{};
    for (final folder in folders) {
      final folderPath = folder.path.toLowerCase();
      DiskSpace? best;
      for (final disk in disks) {
        final diskPath = disk.path.toLowerCase();
        if (folderPath.startsWith(diskPath) &&
            (best == null || diskPath.length > best.path.length)) {
          best = disk;
        }
      }
      if (best != null) matched[best.path.toLowerCase()] = best;
    }
    return matched.values.toList();
  }

  /// Sonarr v3 requires a languageProfileId on add; v4 ignores it.
  /// Returns the first profile id if the endpoint exists, else null.
  Future<int?> _firstLanguageProfileId() async {
    try {
      final list = await _get('languageprofile') as List<dynamic>;
      if (list.isNotEmpty) {
        return (list.first as Map<String, dynamic>)['id'] as int?;
      }
    } catch (_) {}
    return null;
  }

  /// Adds a movie/series with the chosen profile and folder.
  ///
  /// Sonarr-only monitoring (DAN-53): pass [monitor] for a rule-based add
  /// (Sonarr's `addOptions.monitor` picks the seasons — one POST does it), or
  /// pass explicit [seasons] `{'seasonNumber': int, 'monitored': bool}` for
  /// exact-season selection. Exact seasons can't go through `addOptions.monitor`
  /// — Sonarr applies that rule server-side *after* the posted `seasons[]` and
  /// overwrites them — so we add unmonitored (monitor:'none'), commit the
  /// per-season flags with a PUT (which honors them), then search only what we
  /// switched on. Both are ignored for Radarr.
  Future<MediaItem> add({
    required MediaItem item,
    required int qualityProfileId,
    required String rootFolderPath,
    bool searchNow = true,
    String? monitor,
    List<Map<String, dynamic>>? seasons,
  }) async {
    final body = Map<String, dynamic>.from(item.raw);
    body['qualityProfileId'] = qualityProfileId;
    body['rootFolderPath'] = rootFolderPath;
    body['monitored'] = true;

    if (_isRadarr) {
      body['addOptions'] = {'searchForMovie': searchNow};
      final added = await _post(_mediaPath, body) as Map<String, dynamic>;
      return _toItem(added);
    }

    // --- Sonarr ---
    body['seasonFolder'] = true;
    final langId = await _firstLanguageProfileId();
    if (langId != null) body['languageProfileId'] = langId;

    if (seasons == null || seasons.isEmpty) {
      // Rule-based: let Sonarr's monitor rule choose the seasons.
      body['addOptions'] = {
        'searchForMissingEpisodes': searchNow,
        'monitor': monitor ?? 'all',
      };
      final added = await _post(_mediaPath, body) as Map<String, dynamic>;
      return _toItem(added);
    }

    // Exact-season selection. Sonarr populates a new series' episodes
    // asynchronously (via RefreshSeries) and applies addOptions.monitor to them
    // at that point — so any season/episode flags we set before that refresh
    // completes get stomped by the 'none' rule once episodes appear. The fix:
    // add unmonitored, wait for the episode list to populate (proof the initial
    // refresh has consumed addOptions), then commit monitoring for real. We set
    // it at both levels — season flags drive Sonarr's season toggle, and
    // /episode/monitor is the authoritative per-episode flag that actually makes
    // downloads trigger and survives the add-time rule.
    body['addOptions'] = {'searchForMissingEpisodes': false, 'monitor': 'none'};
    final added = await _post(_mediaPath, body) as Map<String, dynamic>;
    final addedId = added['id'] as int?;
    if (addedId == null) return _toItem(added);

    final wanted = {
      for (final s in seasons) s['seasonNumber'] as int: s['monitored'] as bool,
    };

    // Wait (bounded) for the initial refresh to create episodes.
    var episodes = <dynamic>[];
    for (var i = 0; i < 20; i++) {
      episodes = await _get('episode', {'seriesId': '$addedId'}) as List<dynamic>;
      if (episodes.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }

    // Commit season-level monitoring on the authoritative current object.
    final current = await _get('$_mediaPath/$addedId') as Map<String, dynamic>;
    current['monitored'] = true;
    current['seasons'] = ((current['seasons'] as List<dynamic>?) ?? []).map((s) {
      final season = Map<String, dynamic>.from(s as Map<String, dynamic>);
      season['monitored'] = wanted[season['seasonNumber'] as int] ?? false;
      return season;
    }).toList();
    await _put('$_mediaPath/$addedId', current);

    // Commit episode-level monitoring for the chosen seasons — this is what
    // actually makes SeriesSearch (and future grabs) pick them up.
    final wantedEpisodeIds = episodes
        .where((e) => wanted[(e as Map)['seasonNumber'] as int? ?? -1] == true)
        .map((e) => (e as Map)['id'] as int)
        .toList();
    if (wantedEpisodeIds.isNotEmpty) {
      await setEpisodesMonitored(wantedEpisodeIds, true);
    }

    if (searchNow) {
      // SeriesSearch grabs only monitored episodes — exactly the seasons just
      // enabled. Best effort: the series is added and monitored even if this
      // fails, leaving the search for the user to trigger from Sonarr.
      try {
        await _post('command', {'name': 'SeriesSearch', 'seriesId': addedId});
      } catch (_) {}
    }
    return _toItem(added);
  }

  /// Flips monitoring for a movie/series. The v3 PUT expects the full
  /// object back, so send [item]'s raw JSON with the flag changed.
  Future<void> setMonitored(MediaItem item, bool monitored) async {
    final body = Map<String, dynamic>.from(item.raw);
    body['monitored'] = monitored;
    await _put('$_mediaPath/${item.id}', body);
  }

  /// All episodes of a series, sorted by season then episode.
  Future<List<Episode>> getEpisodes(int seriesId) async {
    final list =
        await _get('episode', {'seriesId': '$seriesId'}) as List<dynamic>;
    return list.map((e) => Episode.fromJson(e as Map<String, dynamic>)).toList()
      ..sort(
        (a, b) => a.seasonNumber != b.seasonNumber
            ? a.seasonNumber.compareTo(b.seasonNumber)
            : a.episodeNumber.compareTo(b.episodeNumber),
      );
  }

  Future<void> setEpisodesMonitored(List<int> episodeIds, bool monitored) =>
      _put('episode/monitor', {
        'episodeIds': episodeIds,
        'monitored': monitored,
      });

  /// Interactive search: asks the server to query all indexers for
  /// releases. Slow (30s+) — the server contacts each indexer live.
  /// For Radarr pass [movieId]; for Sonarr pass [seriesId]+[seasonNumber]
  /// for a season search or [episodeId] for a single episode.
  Future<List<Release>> getReleases({
    int? movieId,
    int? seriesId,
    int? seasonNumber,
    int? episodeId,
  }) async {
    final query = <String, String>{
      if (movieId != null) 'movieId': '$movieId',
      if (seriesId != null) 'seriesId': '$seriesId',
      if (seasonNumber != null) 'seasonNumber': '$seasonNumber',
      if (episodeId != null) 'episodeId': '$episodeId',
    };
    final list =
        await _get('release', query, const Duration(seconds: 150))
            as List<dynamic>;
    final releases = list
        .map((e) => Release.fromJson(e as Map<String, dynamic>))
        .toList();
    // Usable releases first; keep the server's quality ordering otherwise.
    final approved = releases.where((r) => !r.rejected).toList();
    final rejected = releases.where((r) => r.rejected).toList();
    return [...approved, ...rejected];
  }

  /// Sends the chosen release to the server's download client.
  Future<void> grabRelease(Release release) =>
      _post('release', {'guid': release.guid, 'indexerId': release.indexerId});

  /// Removes a movie/series from the library, optionally deleting its
  /// files from disk. Never adds an import exclusion, so the item can be
  /// re-added later.
  Future<void> deleteItem(int id, {required bool deleteFiles}) async {
    final query = {
      'deleteFiles': '$deleteFiles',
      _isRadarr ? 'addImportExclusion' : 'addImportListExclusion': 'false',
    };
    final resp = await _client
        .delete(_uri('$_mediaPath/$id', query), headers: _headers)
        .timeout(const Duration(seconds: 60));
    _check(resp);
  }

  void dispose() => _client.close();
}
