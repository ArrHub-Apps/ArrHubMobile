import 'package:flutter/material.dart';

import '../models/episode.dart';
import '../models/media_item.dart';
import '../state/app_state.dart';
import 'release_search_screen.dart';

/// Season/episode browser for a Sonarr series: per-episode status, air
/// dates, monitor toggles, and interactive search at season and episode
/// level.
class EpisodesScreen extends StatefulWidget {
  final ServiceState state;
  final MediaItem item;

  const EpisodesScreen({super.key, required this.state, required this.item});

  @override
  State<EpisodesScreen> createState() => _EpisodesScreenState();
}

class _EpisodesScreenState extends State<EpisodesScreen> {
  List<Episode>? _episodes;
  String? _error;
  final Set<int> _togglingIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _episodes = null;
      _error = null;
    });
    try {
      final episodes = await widget.state.api!.getEpisodes(widget.item.id!);
      if (mounted) setState(() => _episodes = episodes);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _toggleMonitored(Episode episode) async {
    if (_togglingIds.contains(episode.id)) return;
    setState(() => _togglingIds.add(episode.id));
    try {
      await widget.state.api!
          .setEpisodesMonitored([episode.id], !episode.monitored);
      if (mounted) setState(() => episode.monitored = !episode.monitored);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _togglingIds.remove(episode.id));
    }
  }

  void _searchSeason(int seasonNumber) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReleaseSearchScreen(
        state: widget.state,
        item: widget.item,
        seasonNumber: seasonNumber,
      ),
    ));
  }

  void _searchEpisode(Episode episode) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReleaseSearchScreen(
        state: widget.state,
        item: widget.item,
        episodeId: episode.id,
        episodeLabel: episode.code,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Episodes'),
            Text(widget.item.title,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
      body: Builder(builder: (context) {
        if (_error != null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Could not load episodes: $_error',
                    textAlign: TextAlign.center),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          );
        }
        if (_episodes == null) {
          return const Center(child: CircularProgressIndicator());
        }

        // Group by season, newest season first; specials (0) last.
        final seasons = <int, List<Episode>>{};
        for (final e in _episodes!) {
          seasons.putIfAbsent(e.seasonNumber, () => []).add(e);
        }
        final seasonNumbers = seasons.keys.toList()
          ..sort((a, b) {
            if (a == 0) return 1;
            if (b == 0) return -1;
            return b.compareTo(a);
          });

        return ListView(
          children: [
            for (final (index, seasonNumber) in seasonNumbers.indexed)
              _seasonTile(
                context,
                seasonNumber,
                seasons[seasonNumber]!,
                initiallyExpanded: index == 0,
              ),
            const SizedBox(height: 24),
          ],
        );
      }),
    );
  }

  Widget _seasonTile(BuildContext context, int seasonNumber,
      List<Episode> episodes,
      {required bool initiallyExpanded}) {
    final have = episodes.where((e) => e.hasFile).length;
    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      title: Text(seasonNumber == 0 ? 'Specials' : 'Season $seasonNumber'),
      subtitle: Text('$have / ${episodes.length} downloaded'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.manage_search),
            tooltip: 'Search season',
            onPressed: () => _searchSeason(seasonNumber),
          ),
          const Icon(Icons.expand_more),
        ],
      ),
      children: [for (final episode in episodes) _episodeRow(episode)],
    );
  }

  Widget _episodeRow(Episode episode) {
    final theme = Theme.of(context);
    final (statusIcon, statusColor) = episode.hasFile
        ? (Icons.check_circle, Colors.green)
        : !episode.aired
            ? (Icons.event, theme.colorScheme.outline)
            : episode.monitored
                ? (Icons.schedule, Colors.amber)
                : (Icons.remove_circle_outline, theme.colorScheme.outline);
    final dimmed = !episode.monitored && !episode.hasFile;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 24, right: 8),
      leading: SizedBox(
        width: 40,
        child: Text(
          'E${episode.episodeNumber.toString().padLeft(2, "0")}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      title: Text(
        episode.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: dimmed
            ? theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.outline)
            : theme.textTheme.bodyMedium,
      ),
      subtitle: Row(
        children: [
          Icon(statusIcon, size: 12, color: statusColor),
          const SizedBox(width: 4),
          Text(episode.airDateLabel, style: theme.textTheme.bodySmall),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: _togglingIds.contains(episode.id)
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    episode.monitored
                        ? Icons.visibility
                        : Icons.visibility_off,
                    size: 20,
                    color: episode.monitored
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
            tooltip: episode.monitored ? 'Unmonitor' : 'Monitor',
            onPressed: () => _toggleMonitored(episode),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.manage_search, size: 20),
            tooltip: 'Search episode',
            onPressed: () => _searchEpisode(episode),
          ),
        ],
      ),
    );
  }
}
