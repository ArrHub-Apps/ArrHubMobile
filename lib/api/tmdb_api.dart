import 'dart:convert';

import 'package:http/http.dart' as http;

class TmdbException implements Exception {
  final String message;
  TmdbException(this.message);

  @override
  String toString() => message;
}

/// A movie or TV entry from TMDB discovery lists.
class TmdbItem {
  final int id;
  final String title;
  final int? year;
  final String overview;
  final String? posterUrl;
  final String? backdropUrl;
  final double rating;
  final bool isMovie;

  const TmdbItem({
    required this.id,
    required this.title,
    required this.year,
    required this.overview,
    required this.posterUrl,
    this.backdropUrl,
    required this.rating,
    required this.isMovie,
  });

  factory TmdbItem.fromJson(Map<String, dynamic> json, bool isMovie) {
    final dateStr = (isMovie
            ? json['release_date']
            : json['first_air_date']) as String? ??
        '';
    final posterPath = json['poster_path'] as String?;
    final backdropPath = json['backdrop_path'] as String?;
    return TmdbItem(
      id: json['id'] as int,
      title: (isMovie ? json['title'] : json['name']) as String? ?? 'Unknown',
      year: dateStr.length >= 4 ? int.tryParse(dateStr.substring(0, 4)) : null,
      overview: json['overview'] as String? ?? '',
      posterUrl: posterPath == null
          ? null
          : 'https://image.tmdb.org/t/p/w342$posterPath',
      backdropUrl: backdropPath == null
          ? null
          : 'https://image.tmdb.org/t/p/w780$backdropPath',
      rating: (json['vote_average'] as num? ?? 0).toDouble(),
      isMovie: isMovie,
    );
  }
}

/// One cast entry from TMDB's credits endpoint.
class TmdbCastMember {
  final String name;
  final String character;
  final String? profileUrl;

  const TmdbCastMember({
    required this.name,
    required this.character,
    required this.profileUrl,
  });
}

/// Minimal TMDB v3 API client for the Discover tab.
class TmdbApi {
  static const _base = 'https://api.themoviedb.org/3';

  final String apiKey;
  final http.Client _client;

  TmdbApi(this.apiKey, {http.Client? client})
      : _client = client ?? http.Client();

  Future<dynamic> _get(String path, [Map<String, String>? query]) async {
    final uri = Uri.parse('$_base/$path').replace(queryParameters: {
      'api_key': apiKey,
      ...?query,
    });
    final resp = await _client.get(uri).timeout(const Duration(seconds: 30));
    if (resp.statusCode == 401) {
      throw TmdbException('Invalid TMDB API key');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw TmdbException('TMDB error (HTTP ${resp.statusCode})');
    }
    return jsonDecode(resp.body);
  }

  /// Fetches one page (20 items) of a list, dropping items without artwork.
  Future<List<TmdbItem>> _page(String path, bool isMovie, int page,
      [Map<String, String>? query]) async {
    final data =
        await _get(path, {...?query, 'page': '$page'}) as Map<String, dynamic>;
    final results = data['results'] as List<dynamic>? ?? [];
    return results
        .map((e) => TmdbItem.fromJson(e as Map<String, dynamic>, isMovie))
        .where((item) => item.posterUrl != null)
        .toList();
  }

  /// Verifies the API key works.
  Future<void> test() => _get('configuration');

  Future<List<TmdbItem>> trendingMovies(int page) =>
      _page('trending/movie/week', true, page);
  Future<List<TmdbItem>> popularMovies(int page) =>
      _page('movie/popular', true, page);
  Future<List<TmdbItem>> topRatedMovies(int page) =>
      _page('movie/top_rated', true, page);
  Future<List<TmdbItem>> upcomingMovies(int page) =>
      _page('movie/upcoming', true, page);

  Future<List<TmdbItem>> trendingTv(int page) =>
      _page('trending/tv/week', false, page);
  Future<List<TmdbItem>> popularTv(int page) =>
      _page('tv/popular', false, page);
  Future<List<TmdbItem>> topRatedTv(int page) =>
      _page('tv/top_rated', false, page);

  Future<List<TmdbGenre>> genres(bool movies) async {
    final data = await _get('genre/${movies ? "movie" : "tv"}/list')
        as Map<String, dynamic>;
    return (data['genres'] as List<dynamic>? ?? [])
        .map((e) => TmdbGenre(
              id: (e as Map<String, dynamic>)['id'] as int,
              name: e['name'] as String,
            ))
        .toList();
  }

  /// YouTube URL of the best trailer for a title, or null if none.
  /// Prefers official trailers, then any trailer, then teasers.
  Future<String?> trailerUrl(int tmdbId, bool isMovie) async {
    final data = await _get('${isMovie ? "movie" : "tv"}/$tmdbId/videos')
        as Map<String, dynamic>;
    final videos = (data['results'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .where((v) => v['site'] == 'YouTube' && v['key'] != null)
        .toList();
    if (videos.isEmpty) return null;
    int score(Map<String, dynamic> v) {
      final type = v['type'] as String? ?? '';
      final official = v['official'] == true;
      if (type == 'Trailer') return official ? 0 : 1;
      if (type == 'Teaser') return official ? 2 : 3;
      return 4;
    }

    videos.sort((a, b) => score(a).compareTo(score(b)));
    return 'https://www.youtube.com/watch?v=${videos.first['key']}';
  }

  /// Top-billed cast for a title, in TMDB's billing order.
  Future<List<TmdbCastMember>> cast(int tmdbId, bool isMovie) async {
    final data = await _get('${isMovie ? "movie" : "tv"}/$tmdbId/credits')
        as Map<String, dynamic>;
    final cast = data['cast'] as List<dynamic>? ?? [];
    return cast.take(15).map((e) {
      final m = e as Map<String, dynamic>;
      final profilePath = m['profile_path'] as String?;
      return TmdbCastMember(
        name: m['name'] as String? ?? '',
        character: m['character'] as String? ?? '',
        profileUrl: profilePath == null
            ? null
            : 'https://image.tmdb.org/t/p/w185$profilePath',
      );
    }).toList();
  }

  Future<List<TmdbItem>> searchMovies(String query, int page) =>
      _page('search/movie', true, page, {'query': query});
  Future<List<TmdbItem>> searchTv(String query, int page) =>
      _page('search/tv', false, page, {'query': query});

  /// TMDB's "recommended because of this title" list.
  Future<List<TmdbItem>> recommendations(
          int tmdbId, bool isMovie, int page) =>
      _page('${isMovie ? "movie" : "tv"}/$tmdbId/recommendations', isMovie,
          page);

  /// Popular titles within one genre; vote-count floor filters obscure
  /// entries with inflated ratings.
  Future<List<TmdbItem>> byGenre(int genreId, bool isMovie, int page) =>
      _page(
        'discover/${isMovie ? "movie" : "tv"}',
        isMovie,
        page,
        {
          'with_genres': '$genreId',
          'sort_by': 'popularity.desc',
          'vote_count.gte': '100',
        },
      );

  void dispose() => _client.close();
}

class TmdbGenre {
  final int id;
  final String name;
  const TmdbGenre({required this.id, required this.name});
}
