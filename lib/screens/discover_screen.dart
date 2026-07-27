import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/tmdb_api.dart';
import '../state/app_state.dart';
import '../widgets/tmdb_detail_sheet.dart';
import 'person_screen.dart';

/// TMDB-powered discovery: trending/popular/top-rated carousels for
/// movies and TV, with one-tap add to Radarr/Sonarr.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

/// Accumulated pages for one carousel, kept in the screen state so
/// scrolling away or switching tabs doesn't lose or refetch them.
class _SectionData {
  final List<TmdbItem> items = [];
  final Set<int> _ids = {};
  int nextPage = 1;
  bool loading = false;
  bool done = false;
  String? error;

  void addPage(List<TmdbItem> page) {
    for (final item in page) {
      if (_ids.add(item.id)) items.add(item);
    }
    nextPage++;
    if (page.isEmpty || nextPage > 500) done = true; // TMDB caps at 500
  }
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  bool _movies = true;
  final Map<String, _SectionData> _sections = {};
  final Map<bool, Future<List<TmdbGenre>>> _genres = {};
  // Random library picks used to seed "Because you have X" carousels;
  // sampled once per media type so they don't reshuffle every rebuild.
  final Map<bool, List<(String, int)>> _recSeeds = {};
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';
  String? _cachedForKey;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  List<(String, int)> _seedsFor(bool movies, BuildContext context) {
    return _recSeeds.putIfAbsent(movies, () {
      final candidates = movies
          ? context
                .read<RadarrState>()
                .library
                .map((m) => (m.title, m.externalId))
                .where((s) => s.$2 > 0)
                .toList()
          : context
                .read<SonarrState>()
                .library
                .map((s) => (s.title, s.raw['tmdbId'] as int? ?? 0))
                .where((s) => s.$2 > 0)
                .toList();
      candidates.shuffle(Random());
      return candidates.take(3).toList();
    });
  }

  /// Personalized picks first, then curated lists, then genres.
  List<(String, Future<List<TmdbItem>> Function(int))> _sectionDefs(
    TmdbApi api,
    List<TmdbGenre> genres,
    List<(String, int)> seeds,
  ) {
    if (_movies) {
      return [
        for (final (title, id) in seeds)
          (
            'Because you have $title',
            (int page) => api.recommendations(id, true, page),
          ),
        ('Trending', api.trendingMovies),
        ('Popular', api.popularMovies),
        ('Top Rated', api.topRatedMovies),
        ('Upcoming', api.upcomingMovies),
        for (final g in genres)
          (g.name, (int page) => api.byGenre(g.id, true, page)),
      ];
    }
    return [
      for (final (title, id) in seeds)
        (
          'Because you have $title',
          (int page) => api.recommendations(id, false, page),
        ),
      ('Trending', api.trendingTv),
      ('Popular', api.popularTv),
      ('Top Rated', api.topRatedTv),
      for (final g in genres)
        (g.name, (int page) => api.byGenre(g.id, false, page)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tmdb = context.watch<TmdbState>();
    if (!tmdb.isConfigured) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.explore_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              const Text(
                'Discover needs a free TMDB API key.\n\n'
                'Create one at themoviedb.org (Settings > API), then add it '
                'in this app\'s Settings tab.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final api = tmdb.api!;
    if (_cachedForKey != api.apiKey) {
      _sections.clear();
      _genres.clear();
      _cachedForKey = api.apiKey;
    }

    // Library tmdb ids so carousels can show what's already added.
    final inLibrary = _movies
        ? context.watch<RadarrState>().library.map((m) => m.externalId).toSet()
        : context
              .watch<SonarrState>()
              .library
              .map((s) => s.raw['tmdbId'] as int? ?? -1)
              .toSet();

    final genresFuture = _genres.putIfAbsent(
      _movies,
      () => api.genres(_movies),
    );
    final searching = _query.isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Movies')),
              ButtonSegment(value: false, label: Text('TV Shows')),
            ],
            showSelectedIcon: false,
            selected: {_movies},
            onSelectionChanged: (s) => setState(() => _movies = s.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _searchController,
            onChanged: _onQueryChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search TMDB for ${_movies ? "movies" : "shows"}...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _searchDebounce?.cancel();
                        setState(() => _query = '');
                      },
                    ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        Expanded(
          child: searching
              ? Column(
                  children: [
                    // People matching the query (DAN-52) — tap one to see their
                    // filmography. Media-type agnostic, so keyed by query only.
                    _PeopleStrip(
                      key: ValueKey('people|$_query'),
                      api: api,
                      query: _query,
                    ),
                    Expanded(
                      child: _SearchResults(
                        key: ValueKey('search$_movies$_query'),
                        data: _sections.putIfAbsent(
                          'search|$_movies|$_query',
                          _SectionData.new,
                        ),
                        fetchPage: (page) => _movies
                            ? api.searchMovies(_query, page)
                            : api.searchTv(_query, page),
                        inLibraryIds: inLibrary,
                      ),
                    ),
                  ],
                )
              : FutureBuilder<List<TmdbGenre>>(
                  future: genresFuture,
                  builder: (context, snapshot) {
                    final defs = _sectionDefs(
                      api,
                      snapshot.data ?? [],
                      _seedsFor(_movies, context),
                    );
                    return ListView.builder(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewPadding.bottom,
                      ),
                      itemCount: defs.length,
                      itemBuilder: (context, i) {
                        final (title, fetch) = defs[i];
                        final data = _sections.putIfAbsent(
                          '$_movies|$title',
                          _SectionData.new,
                        );
                        return _Section(
                          key: ValueKey('$_movies$title'),
                          title: title,
                          data: data,
                          fetchPage: fetch,
                          inLibraryIds: inLibrary,
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Horizontal strip of people matching the search query (DAN-52). Renders
/// nothing while loading or when no people (with artwork) match; tapping one
/// opens their filmography. Loads a single page — enough for a "did you mean
/// this actor" hint above the title results.
class _PeopleStrip extends StatefulWidget {
  final TmdbApi api;
  final String query;

  const _PeopleStrip({super.key, required this.api, required this.query});

  @override
  State<_PeopleStrip> createState() => _PeopleStripState();
}

class _PeopleStripState extends State<_PeopleStrip> {
  late final Future<List<TmdbPerson>> _future = _load();

  Future<List<TmdbPerson>> _load() async {
    try {
      final people = await widget.api.searchPerson(widget.query, 1);
      return people.where((p) => p.profileUrl != null).take(10).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<TmdbPerson>>(
      future: _future,
      builder: (context, snapshot) {
        final people = snapshot.data ?? [];
        if (people.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'People',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            SizedBox(
              height: 104,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: people.length,
                itemBuilder: (context, i) => _PersonChip(person: people[i]),
              ),
            ),
            const Divider(height: 17),
          ],
        );
      },
    );
  }
}

class _PersonChip extends StatelessWidget {
  final TmdbPerson person;
  const _PersonChip({required this.person});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => PersonScreen(person: person))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          width: 68,
          child: Column(
            children: [
              ClipOval(
                child: person.profileUrl == null
                    ? Container(
                        width: 60,
                        height: 60,
                        color: theme.colorScheme.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: Text(
                          person.name.isEmpty ? '?' : person.name[0],
                          style: theme.textTheme.titleMedium,
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: person.profileUrl!,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(
                          width: 60,
                          height: 60,
                          color: theme.colorScheme.surfaceContainerHighest,
                        ),
                        errorWidget: (_, _, _) => Container(
                          width: 60,
                          height: 60,
                          color: theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
              ),
              const SizedBox(height: 4),
              Text(
                person.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vertical, infinitely paginated search results.
class _SearchResults extends StatefulWidget {
  final _SectionData data;
  final Future<List<TmdbItem>> Function(int page) fetchPage;
  final Set<int> inLibraryIds;

  const _SearchResults({
    super.key,
    required this.data,
    required this.fetchPage,
    required this.inLibraryIds,
  });

  @override
  State<_SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends State<_SearchResults> {
  @override
  void initState() {
    super.initState();
    if (widget.data.items.isEmpty) _loadMore();
  }

  Future<void> _loadMore() async {
    final data = widget.data;
    if (data.loading || data.done) return;
    data.loading = true;
    data.error = null;
    if (mounted) setState(() {});
    try {
      final page = await widget.fetchPage(data.nextPage);
      data.addPage(page);
    } catch (e) {
      data.error = e.toString();
    } finally {
      data.loading = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final theme = Theme.of(context);
    if (data.items.isEmpty) {
      if (data.loading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (data.error != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Search failed: ${data.error}', textAlign: TextAlign.center),
              TextButton(onPressed: _loadMore, child: const Text('Retry')),
            ],
          ),
        );
      }
      return const Center(child: Text('No results'));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels > n.metrics.maxScrollExtent - 800) {
          _loadMore();
        }
        return false;
      },
      child: ListView.builder(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewPadding.bottom,
        ),
        itemCount: data.items.length + (data.done ? 0 : 1),
        itemBuilder: (context, i) {
          if (i >= data.items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final item = data.items[i];
          final inLibrary = widget.inLibraryIds.contains(item.id);
          return InkWell(
            onTap: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => TmdbDetailSheet(item: item),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                      imageUrl: item.posterUrl!,
                      width: 60,
                      height: 90,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        width: 60,
                        height: 90,
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                      errorWidget: (_, _, _) => Container(
                        width: 60,
                        height: 90,
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        Row(
                          children: [
                            if (item.year != null) ...[
                              Text(
                                '${item.year}',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(width: 8),
                            ],
                            const Icon(
                              Icons.star,
                              size: 12,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              item.rating.toStringAsFixed(1),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                        if (item.overview.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            item.overview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (inLibrary) ...[
                    const SizedBox(width: 8),
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 20,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Section extends StatefulWidget {
  final String title;
  final _SectionData data;
  final Future<List<TmdbItem>> Function(int page) fetchPage;
  final Set<int> inLibraryIds;

  const _Section({
    super.key,
    required this.title,
    required this.data,
    required this.fetchPage,
    required this.inLibraryIds,
  });

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  @override
  void initState() {
    super.initState();
    if (widget.data.items.isEmpty) _loadMore();
  }

  Future<void> _loadMore() async {
    final data = widget.data;
    if (data.loading || data.done) return;
    data.loading = true;
    data.error = null;
    if (mounted) setState(() {});
    try {
      final page = await widget.fetchPage(data.nextPage);
      data.addPage(page);
    } catch (e) {
      data.error = e.toString();
    } finally {
      data.loading = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            widget.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        SizedBox(
          height: 210,
          child: Builder(
            builder: (context) {
              if (data.items.isEmpty) {
                if (data.loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (data.error != null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Could not load: ${data.error}',
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                          TextButton(
                            onPressed: _loadMore,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              }
              // Fetch the next page when scrolled near the end of the row.
              return NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) {
                    _loadMore();
                  }
                  return false;
                },
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: data.items.length + (data.done ? 0 : 1),
                  itemBuilder: (context, i) {
                    if (i >= data.items.length) {
                      return const SizedBox(
                        width: 60,
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    return _DiscoverTile(
                      item: data.items[i],
                      inLibrary: widget.inLibraryIds.contains(data.items[i].id),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DiscoverTile extends StatelessWidget {
  final TmdbItem item;
  final bool inLibrary;

  const _DiscoverTile({required this.item, required this.inLibrary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => TmdbDetailSheet(item: item),
        ),
        child: SizedBox(
          width: 110,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: item.posterUrl!,
                      width: 110,
                      height: 165,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        width: 110,
                        height: 165,
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                      errorWidget: (_, _, _) => Container(
                        width: 110,
                        height: 165,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.image_outlined,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                  ),
                  if (inLibrary)
                    const Positioned(
                      top: 6,
                      right: 6,
                      child: Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 20,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.star, size: 12, color: Colors.amber),
                  const SizedBox(width: 2),
                  Text(
                    item.rating.toStringAsFixed(1),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.year?.toString() ?? '',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
