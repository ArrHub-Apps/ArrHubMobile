import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/tmdb_api.dart';
import '../state/app_state.dart';
import '../widgets/poster.dart';
import '../widgets/tmdb_detail_sheet.dart';

enum _TypeFilter { all, movie, tv }

enum _SortMode { popularity, title, year }

/// A person's filmography (DAN-52) — reached by tapping a cast member on a
/// title's detail sheet, or a person result in Discover search. Shows their
/// known movies and shows with Movies/TV filtering and Popular/A–Z/Year sort;
/// tapping a title opens its detail sheet.
class PersonScreen extends StatefulWidget {
  final TmdbPerson person;
  const PersonScreen({super.key, required this.person});

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  Future<List<TmdbItem>>? _future;
  _TypeFilter _typeFilter = _TypeFilter.all;
  _SortMode _sortMode = _SortMode.popularity;
  // Only meaningful while sorting by year — re-tapping Year flips this, so it
  // doubles as its own newest/oldest toggle (matches desktop DiscoverPerson).
  bool _yearNewestFirst = true;

  void _selectSort(_SortMode mode) {
    setState(() {
      if (mode == _SortMode.year && _sortMode == _SortMode.year) {
        _yearNewestFirst = !_yearNewestFirst;
        return;
      }
      _sortMode = mode;
      if (mode == _SortMode.year) _yearNewestFirst = true;
    });
  }

  /// [credits] is already popularity-sorted by TmdbApi.personCredits(), so
  /// filtering alone preserves that order — 'popularity' needs no extra sort.
  List<TmdbItem> _display(List<TmdbItem> credits) {
    var list = credits;
    if (_typeFilter == _TypeFilter.movie) {
      list = list.where((i) => i.isMovie).toList();
    } else if (_typeFilter == _TypeFilter.tv) {
      list = list.where((i) => !i.isMovie).toList();
    }
    if (_sortMode == _SortMode.title) {
      list = [
        ...list,
      ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    } else if (_sortMode == _SortMode.year) {
      list = [...list]
        ..sort((a, b) {
          if (a.year == null) return b.year == null ? 0 : 1;
          if (b.year == null) return -1;
          return _yearNewestFirst
              ? b.year!.compareTo(a.year!)
              : a.year!.compareTo(b.year!);
        });
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final tmdb = context.watch<TmdbState>();
    final api = tmdb.api;
    if (api == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.person.name)),
        body: const Center(child: Text('TMDB is not configured.')),
      );
    }
    _future ??= api.personCredits(widget.person.id);

    // In-library ids across both services, since a person spans movies and TV.
    final movieIds = context
        .watch<RadarrState>()
        .library
        .map((m) => m.externalId)
        .toSet();
    final tvIds = context
        .watch<SonarrState>()
        .library
        .map((s) => s.raw['tmdbId'] as int? ?? -1)
        .toSet();
    bool inLibrary(TmdbItem i) =>
        i.isMovie ? movieIds.contains(i.id) : tvIds.contains(i.id);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            _Avatar(person: widget.person),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.person.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: FutureBuilder<List<TmdbItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Could not load filmography: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final credits = snapshot.data ?? [];
          if (credits.isEmpty) {
            return const Center(child: Text('No known movies or shows found.'));
          }
          final displayed = _display(credits);
          return Column(
            children: [
              _Filters(
                typeFilter: _typeFilter,
                sortMode: _sortMode,
                yearNewestFirst: _yearNewestFirst,
                onType: (t) => setState(() => _typeFilter = t),
                onSort: _selectSort,
              ),
              Expanded(
                child: displayed.isEmpty
                    ? Center(
                        child: Text(
                          'No ${switch (_typeFilter) {
                            _TypeFilter.movie => 'movies',
                            _TypeFilter.tv => 'TV shows',
                            _TypeFilter.all => 'titles',
                          }} match this filter.',
                        ),
                      )
                    : GridView.builder(
                        padding: EdgeInsets.fromLTRB(
                          12,
                          4,
                          12,
                          MediaQuery.of(context).viewPadding.bottom + 12,
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 120,
                              childAspectRatio: 0.52,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                        itemCount: displayed.length,
                        itemBuilder: (context, i) => _FilmTile(
                          item: displayed[i],
                          inLibrary: inLibrary(displayed[i]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final TmdbPerson person;
  const _Avatar({required this.person});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipOval(
      child: person.profileUrl == null
          ? Container(
              width: 36,
              height: 36,
              color: theme.colorScheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: Text(
                person.name.isEmpty ? '?' : person.name[0],
                style: theme.textTheme.titleMedium,
              ),
            )
          : CachedNetworkImage(
              imageUrl: person.profileUrl!,
              width: 36,
              height: 36,
              fit: BoxFit.cover,
            ),
    );
  }
}

class _Filters extends StatelessWidget {
  final _TypeFilter typeFilter;
  final _SortMode sortMode;
  final bool yearNewestFirst;
  final ValueChanged<_TypeFilter> onType;
  final ValueChanged<_SortMode> onSort;

  const _Filters({
    required this.typeFilter,
    required this.sortMode,
    required this.yearNewestFirst,
    required this.onType,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final yearLabel = sortMode == _SortMode.year
        ? (yearNewestFirst ? 'Year ↓' : 'Year ↑')
        : 'Year';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          _PillGroup(
            children: [
              _Pill(
                label: 'All',
                active: typeFilter == _TypeFilter.all,
                onTap: () => onType(_TypeFilter.all),
              ),
              _Pill(
                label: 'Movies',
                active: typeFilter == _TypeFilter.movie,
                onTap: () => onType(_TypeFilter.movie),
              ),
              _Pill(
                label: 'TV',
                active: typeFilter == _TypeFilter.tv,
                onTap: () => onType(_TypeFilter.tv),
              ),
            ],
          ),
          _PillGroup(
            children: [
              _Pill(
                label: 'Popular',
                active: sortMode == _SortMode.popularity,
                onTap: () => onSort(_SortMode.popularity),
              ),
              _Pill(
                label: 'A–Z',
                active: sortMode == _SortMode.title,
                onTap: () => onSort(_SortMode.title),
              ),
              _Pill(
                label: yearLabel,
                active: sortMode == _SortMode.year,
                onTap: () => onSort(_SortMode.year),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PillGroup extends StatelessWidget {
  final List<Widget> children;
  const _PillGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Pill({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: active ? theme.colorScheme.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: active
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilmTile extends StatelessWidget {
  final TmdbItem item;
  final bool inLibrary;

  const _FilmTile({required this.item, required this.inLibrary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => TmdbDetailSheet(item: item),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: Poster(url: item.posterUrl)),
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
          ),
          const SizedBox(height: 4),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          Row(
            children: [
              const Icon(Icons.star, size: 11, color: Colors.amber),
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
    );
  }
}
