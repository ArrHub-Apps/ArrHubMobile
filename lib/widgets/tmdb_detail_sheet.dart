import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/tmdb_api.dart';
import '../screens/add_search_screen.dart' show AddSheet;
import '../state/app_state.dart';
import 'poster.dart' show SheetBackdropHeader;

/// "Watch trailer" button backed by TMDB's videos endpoint. Renders
/// nothing while loading, if TMDB isn't configured, or if the title has
/// no YouTube trailer.
class TrailerButton extends StatefulWidget {
  final int tmdbId;
  final bool isMovie;
  final bool compact; // icon-only, for tight button rows

  const TrailerButton({
    super.key,
    required this.tmdbId,
    required this.isMovie,
    this.compact = false,
  });

  @override
  State<TrailerButton> createState() => _TrailerButtonState();
}

class _TrailerButtonState extends State<TrailerButton> {
  Future<String?>? _future;

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open trailer')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tmdb = context.watch<TmdbState>();
    if (tmdb.api == null) return const SizedBox.shrink();
    _future ??= tmdb.api!
        .trailerUrl(widget.tmdbId, widget.isMovie)
        .catchError((_) => null);
    return FutureBuilder<String?>(
      future: _future,
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null) return const SizedBox.shrink();
        if (widget.compact) {
          return Padding(
            padding: const EdgeInsets.only(left: 12),
            child: OutlinedButton(
              onPressed: () => _open(url),
              child: const Icon(Icons.play_arrow),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _open(url),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Watch Trailer'),
            ),
          ),
        );
      },
    );
  }
}

/// Detail sheet for a TMDB title: artwork, overview, add-to-server button,
/// and a carousel of similar titles. Used by Discover and by the library's
/// own suggestion carousels.
class TmdbDetailSheet extends StatefulWidget {
  final TmdbItem item;
  const TmdbDetailSheet({super.key, required this.item});

  @override
  State<TmdbDetailSheet> createState() => _TmdbDetailSheetState();
}

class _TmdbDetailSheetState extends State<TmdbDetailSheet> {
  bool _looking = false;
  String? _error;

  Future<void> _startAdd() async {
    final item = widget.item;
    final service = item.isMovie
        ? context.read<RadarrState>() as ServiceState
        : context.read<SonarrState>() as ServiceState;
    if (service.api == null) {
      setState(
        () => _error =
            'Set up ${item.isMovie ? "Radarr" : "Sonarr"} in Settings first.',
      );
      return;
    }
    setState(() {
      _looking = true;
      _error = null;
    });
    try {
      final match = await service.api!.lookupByTmdbId(item.id);
      if (!mounted) return;
      if (match == null) {
        setState(
          () => _error =
              'Your ${item.isMovie ? "Radarr" : "Sonarr"} could not find this title.',
        );
        return;
      }
      if (match.inLibrary) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${match.title}" is already in your library'),
          ),
        );
        return;
      }
      Navigator.of(context).pop();
      final added = await showModalBottomSheet<bool>(
        // ignore: use_build_context_synchronously
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => AddSheet(state: service, item: match),
      );
      if (added == true) service.refreshLibrary();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _looking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SheetBackdropHeader(
                backdropUrl: item.backdropUrl,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: item.posterUrl!,
                        width: 80,
                        height: 120,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title, style: theme.textTheme.titleLarge),
                          if (item.year != null) Text('${item.year}'),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.star,
                                size: 14,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${item.rating.toStringAsFixed(1)} / 10',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    item.overview.isEmpty
                        ? 'No overview available.'
                        : item.overview,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!,
                          style: TextStyle(color: theme.colorScheme.error)),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _looking ? null : _startAdd,
                            icon: _looking
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.add),
                            label: Text(
                              'Add to ${item.isMovie ? "Radarr" : "Sonarr"}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        TrailerButton(
                          tmdbId: item.id,
                          isMovie: item.isMovie,
                          compact: true,
                        ),
                      ],
                    ),
                    CastRow(tmdbId: item.id, isMovie: item.isMovie),
                    SuggestedCarousel(tmdbId: item.id, isMovie: item.isMovie),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal cast strip backed by TMDB's credits endpoint. Renders
/// nothing while loading, if TMDB isn't configured, or if the title has
/// no cast listed.
class CastRow extends StatefulWidget {
  final int tmdbId;
  final bool isMovie;

  const CastRow({super.key, required this.tmdbId, required this.isMovie});

  @override
  State<CastRow> createState() => _CastRowState();
}

class _CastRowState extends State<CastRow> {
  Future<List<TmdbCastMember>>? _future;

  @override
  Widget build(BuildContext context) {
    final tmdb = context.watch<TmdbState>();
    if (tmdb.api == null) return const SizedBox.shrink();
    _future ??= tmdb.api!
        .cast(widget.tmdbId, widget.isMovie)
        .catchError((_) => <TmdbCastMember>[]);
    return FutureBuilder<List<TmdbCastMember>>(
      future: _future,
      builder: (context, snapshot) {
        final cast = snapshot.data ?? [];
        if (cast.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(
                'Cast',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            SizedBox(
              height: 108,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: cast.length,
                itemBuilder: (context, i) => _CastTile(member: cast[i]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CastTile extends StatelessWidget {
  final TmdbCastMember member;
  const _CastTile({required this.member});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            ClipOval(
              child: member.profileUrl == null
                  ? Container(
                      width: 56,
                      height: 56,
                      color: theme.colorScheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: Text(
                        member.name.isEmpty ? '?' : member.name[0],
                        style: theme.textTheme.titleMedium,
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: member.profileUrl!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        width: 56,
                        height: 56,
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                      errorWidget: (_, _, _) => Container(
                        width: 56,
                        height: 56,
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            Text(
              member.character,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal "Suggested" carousel of TMDB recommendations for a title.
/// Renders nothing when TMDB isn't configured or has no suggestions.
class SuggestedCarousel extends StatefulWidget {
  final int tmdbId;
  final bool isMovie;

  const SuggestedCarousel({
    super.key,
    required this.tmdbId,
    required this.isMovie,
  });

  @override
  State<SuggestedCarousel> createState() => _SuggestedCarouselState();
}

class _SuggestedCarouselState extends State<SuggestedCarousel> {
  Future<List<TmdbItem>>? _future;

  @override
  Widget build(BuildContext context) {
    final tmdb = context.watch<TmdbState>();
    if (tmdb.api == null) return const SizedBox.shrink();
    _future ??= tmdb.api!.recommendations(widget.tmdbId, widget.isMovie, 1);

    final inLibrary = widget.isMovie
        ? context.watch<RadarrState>().library.map((m) => m.externalId).toSet()
        : context
              .watch<SonarrState>()
              .library
              .map((s) => s.raw['tmdbId'] as int? ?? -1)
              .toSet();

    return FutureBuilder<List<TmdbItem>>(
      future: _future,
      builder: (context, snapshot) {
        final items = snapshot.data ?? [];
        if (snapshot.connectionState == ConnectionState.done && items.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(
                'Suggested',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            SizedBox(
              height: 135,
              child: items.isEmpty
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: items.length,
                      itemBuilder: (context, i) => _SuggestedTile(
                        item: items[i],
                        inLibrary: inLibrary.contains(items[i].id),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _SuggestedTile extends StatelessWidget {
  final TmdbItem item;
  final bool inLibrary;

  const _SuggestedTile({required this.item, required this.inLibrary});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => TmdbDetailSheet(item: item),
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: item.posterUrl!,
                width: 90,
                height: 135,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(
                  width: 90,
                  height: 135,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                errorWidget: (_, _, _) => Container(
                  width: 90,
                  height: 135,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
            if (inLibrary)
              const Positioned(
                top: 4,
                right: 4,
                child: Icon(Icons.check_circle, color: Colors.green, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}
