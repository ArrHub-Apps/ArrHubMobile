import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_item.dart';
import '../models/server_config.dart';
import '../state/app_state.dart';
import '../widgets/poster.dart';
import '../widgets/tmdb_detail_sheet.dart';
import 'add_search_screen.dart';
import 'episodes_screen.dart';
import 'release_search_screen.dart';

/// Library list for one service, with local filtering and a FAB that
/// opens the add-new search flow. Shared by the Movies and TV tabs.
class LibraryScreen extends StatefulWidget {
  final ServiceState state;
  const LibraryScreen({super.key, required this.state});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

enum _SortBy { title, added, year, rating }

class _LibraryScreenState extends State<LibraryScreen> {
  static const _columnsPrefKey = 'library_columns';

  final _filterController = TextEditingController();
  String _filter = '';
  _SortBy _sortBy = _SortBy.title;
  MediaStatus? _statusFilter; // null = all
  int _columns = 3;
  double _lastAppliedScale = 1;

  String get _mediaLabel =>
      widget.state.type == ServerType.radarr ? 'movies' : 'shows';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getInt(_columnsPrefKey);
      if (saved != null && mounted) {
        setState(() => _columns = saved.clamp(2, 5));
      }
    });
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  void _onScaleStart(ScaleStartDetails details) {
    _lastAppliedScale = 1;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) return; // don't fight vertical scrolling
    final relative = details.scale / _lastAppliedScale;
    // Pinch out = bigger posters = fewer columns; pinch in = more.
    if (relative > 1.25 && _columns > 2) {
      setState(() => _columns--);
      _lastAppliedScale = details.scale;
    } else if (relative < 0.8 && _columns < 5) {
      setState(() => _columns++);
      _lastAppliedScale = details.scale;
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setInt(_columnsPrefKey, _columns));
  }

  List<MediaItem> _visibleItems() {
    final state = widget.state;
    var items = state.library.where((m) {
      if (_filter.isNotEmpty &&
          !m.title.toLowerCase().contains(_filter.toLowerCase())) {
        return false;
      }
      if (_statusFilter != null && state.statusFor(m) != _statusFilter) {
        return false;
      }
      return true;
    }).toList();
    switch (_sortBy) {
      case _SortBy.title:
        break; // library is already title-sorted
      case _SortBy.added:
        items.sort(
          (a, b) => (b.added ?? DateTime(0)).compareTo(a.added ?? DateTime(0)),
        );
      case _SortBy.year:
        items.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
      case _SortBy.rating:
        items.sort((a, b) => b.rating.compareTo(a.rating));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final state = widget.state;
        if (!state.isConfigured) {
          return _Message(
            icon: Icons.settings_outlined,
            text:
                'Set up your ${state.type == ServerType.radarr ? "Radarr" : "Sonarr"} '
                'server in the Settings tab first.',
          );
        }
        if (state.loading && state.library.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.error != null && state.library.isEmpty) {
          return _Message(
            icon: Icons.error_outline,
            text: state.error!,
            action: TextButton(
              onPressed: state.refreshLibrary,
              child: const Text('Retry'),
            ),
          );
        }

        final items = _visibleItems();

        return Scaffold(
          body: RefreshIndicator(
            onRefresh: state.refreshLibrary,
            child: Column(
              children: [
                if (state.error != null && state.library.isNotEmpty)
                  Container(
                    width: double.infinity,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_off,
                            size: 16, color: Colors.amber),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Couldn\'t refresh — showing last known library',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact),
                          onPressed: state.refreshLibrary,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _filterController,
                          onChanged: (v) => setState(() => _filter = v),
                          decoration: InputDecoration(
                            hintText:
                                'Filter ${state.library.length} $_mediaLabel...',
                            prefixIcon: const Icon(Icons.filter_list),
                            suffixIcon: _filter.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _filterController.clear();
                                      setState(() => _filter = '');
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
                      PopupMenuButton<_SortBy>(
                        icon: Icon(
                          Icons.swap_vert,
                          color: _sortBy == _SortBy.title
                              ? null
                              : Theme.of(context).colorScheme.primary,
                        ),
                        tooltip: 'Sort',
                        initialValue: _sortBy,
                        onSelected: (v) => setState(() => _sortBy = v),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: _SortBy.title,
                            child: Text('Title'),
                          ),
                          PopupMenuItem(
                            value: _SortBy.added,
                            child: Text('Recently added'),
                          ),
                          PopupMenuItem(
                            value: _SortBy.year,
                            child: Text('Year'),
                          ),
                          PopupMenuItem(
                            value: _SortBy.rating,
                            child: Text('Rating'),
                          ),
                        ],
                      ),
                      PopupMenuButton<Object>(
                        icon: Icon(
                          Icons.filter_alt_outlined,
                          color: _statusFilter == null
                              ? null
                              : Theme.of(context).colorScheme.primary,
                        ),
                        tooltip: 'Filter by status',
                        initialValue: _statusFilter ?? 'all',
                        onSelected: (v) => setState(
                          () => _statusFilter = v is MediaStatus ? v : null,
                        ),
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'all', child: Text('All')),
                          for (final status in MediaStatus.values)
                            PopupMenuItem(
                              value: status,
                              child: Text(StatusIcon.label(status)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? _Message(
                          icon: Icons.video_library_outlined,
                          text: _filter.isEmpty
                              ? 'No $_mediaLabel in your library yet.\nTap + to add one.'
                              : 'No $_mediaLabel match "$_filter".',
                        )
                      : GestureDetector(
                          onScaleStart: _onScaleStart,
                          onScaleUpdate: _onScaleUpdate,
                          onScaleEnd: _onScaleEnd,
                          child: Builder(builder: (context) {
                            final width = MediaQuery.sizeOf(context).width;
                            // The pinch preference picks a poster size on a
                            // ~420dp phone; wider screens (tablets,
                            // landscape) get proportionally more columns so
                            // posters keep that size instead of growing.
                            var columns = (width * _columns / 420).round();
                            if (columns < _columns) columns = _columns;
                            // Keep the 2:3 poster plus a fixed 40px text
                            // block at any zoom level.
                            final cellWidth =
                                (width - 24 - (columns - 1) * 10) / columns;
                            final ratio =
                                cellWidth / (cellWidth * 1.5 + 40);
                            return GridView.builder(
                              padding: EdgeInsets.fromLTRB(
                                12,
                                8,
                                12,
                                88 + MediaQuery.of(context).viewPadding.bottom,
                              ),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 12,
                                childAspectRatio: ratio,
                              ),
                              itemCount: items.length,
                              itemBuilder: (context, i) => _PosterTile(
                                  item: items[i], state: widget.state),
                            );
                          }),
                        ),
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            heroTag: 'add_${state.type.name}',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AddSearchScreen(state: state)),
            ),
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }
}

/// Opens the right search surface for an item: release search for
/// movies, the episode browser (which hosts per-episode search) for
/// shows.
void _openItemSearch(
    BuildContext context, ServiceState state, MediaItem item) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => state.type == ServerType.radarr
          ? ReleaseSearchScreen(state: state, item: item)
          : EpisodesScreen(state: state, item: item),
    ),
  );
}

class _PosterTile extends StatelessWidget {
  final MediaItem item;
  final ServiceState state;
  const _PosterTile({required this.item, required this.state});

  Future<void> _toggleMonitored(BuildContext context) async {
    final target = !item.monitored;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await state.setMonitored(item, target);
      messenger.showSnackBar(SnackBar(
        content: Text(target
            ? 'Monitoring "${item.title}"'
            : 'Stopped monitoring "${item.title}"'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  void _showQuickActions(BuildContext context) {
    final isMovie = state.type == ServerType.radarr;
    final error = Theme.of(context).colorScheme.error;
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Poster(url: item.posterUrl, width: 32),
              title: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: item.year == null ? null : Text('${item.year}'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                  isMovie ? Icons.manage_search : Icons.video_library_outlined),
              title: Text(isMovie ? 'Interactive Search' : 'Episodes'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openItemSearch(context, state, item);
              },
            ),
            ListTile(
              leading: Icon(item.monitored
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined),
              title: Text(
                  item.monitored ? 'Stop monitoring' : 'Start monitoring'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _toggleMonitored(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: error),
              title: Text('Delete...', style: TextStyle(color: error)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmAndDeleteItem(context, state, item);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onLongPress: () => _showQuickActions(context),
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _DetailSheet(item: item, state: state),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Poster(url: item.posterUrl)),
          const SizedBox(height: 6),
          // Fixed two-line text block so every poster is the same height,
          // whether the title wraps or not.
          SizedBox(
            height: 34,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusIcon(status: state.statusFor(item), size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSheet extends StatelessWidget {
  final MediaItem item;
  final ServiceState state;
  const _DetailSheet({required this.item, required this.state});

  @override
  Widget build(BuildContext context) {
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
                backdropUrl: item.fanartUrl,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Poster(url: item.posterUrl, width: 80),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (item.year != null)
                            Text(
                              '${item.year}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              StatusIcon(
                                  status: state.statusFor(item), size: 14),
                              const SizedBox(width: 4),
                              Text(
                                StatusIcon.label(state.statusFor(item)),
                                style: Theme.of(context).textTheme.bodySmall,
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
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _openItemSearch(context, state, item),
                            icon: Icon(state.type == ServerType.radarr
                                ? Icons.manage_search
                                : Icons.video_library_outlined),
                            label: Text(state.type == ServerType.radarr
                                ? 'Search'
                                : 'Episodes'),
                          ),
                        ),
                        if (_tmdbId > 0)
                          TrailerButton(
                            tmdbId: _tmdbId,
                            isMovie: state.type == ServerType.radarr,
                            compact: true,
                          ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: () async {
                            final deleted = await _confirmAndDeleteItem(
                                context, state, item);
                            if (deleted && context.mounted) {
                              Navigator.of(context).pop();
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).colorScheme.error,
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          child: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    if (_tmdbId > 0) ...[
                      CastRow(
                        tmdbId: _tmdbId,
                        isMovie: state.type == ServerType.radarr,
                      ),
                      SuggestedCarousel(
                        tmdbId: _tmdbId,
                        isMovie: state.type == ServerType.radarr,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int get _tmdbId => state.type == ServerType.radarr
      ? item.externalId
      : (item.raw['tmdbId'] as int? ?? 0);
}

/// Delete confirmation + API call, shared by the detail sheet and the
/// long-press quick actions. Returns true when the item was removed.
Future<bool> _confirmAndDeleteItem(
    BuildContext context, ServiceState state, MediaItem item) async {
  var deleteFiles = false;
  final mediaLabel = state.type == ServerType.radarr ? 'movie' : 'show';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text('Delete "${item.title}"?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This removes the $mediaLabel from your library. It can be re-added later.',
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Also delete files from disk'),
              subtitle: item.sizeOnDisk == 0
                  ? const Text('No files on disk')
                  : deleteFiles
                      ? Text(
                          '${item.sizeLabel} will be permanently deleted',
                          style: TextStyle(
                            color: Theme.of(dialogContext).colorScheme.error,
                          ),
                        )
                      : Text('${item.sizeLabel} on disk'),
              value: deleteFiles,
              onChanged: item.sizeOnDisk == 0
                  ? null
                  : (v) => setDialogState(() => deleteFiles = v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  try {
    await state.api!.deleteItem(item.id!, deleteFiles: deleteFiles);
    unawaited(state.refreshLibrary());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deleteFiles
                ? 'Deleted "${item.title}" and its files'
                : 'Removed "${item.title}" from library',
          ),
        ),
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
    return false;
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  const _Message({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}
