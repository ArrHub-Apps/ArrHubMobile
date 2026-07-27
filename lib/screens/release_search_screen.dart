import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../models/release.dart';
import '../models/server_config.dart';
import '../state/app_state.dart';

/// Interactive search: shows every release the indexers found for a movie
/// (Radarr) or a season (Sonarr) and lets the user grab one.
class ReleaseSearchScreen extends StatefulWidget {
  final ServiceState state;
  final MediaItem item;
  final int? seasonNumber; // Sonarr season search
  final int? episodeId; // Sonarr single-episode search
  final String? episodeLabel; // e.g. "S02E05 — The One Where..."

  const ReleaseSearchScreen({
    super.key,
    required this.state,
    required this.item,
    this.seasonNumber,
    this.episodeId,
    this.episodeLabel,
  });

  @override
  State<ReleaseSearchScreen> createState() => _ReleaseSearchScreenState();
}

class _ReleaseSearchScreenState extends State<ReleaseSearchScreen> {
  List<Release>? _releases;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() {
      _releases = null;
      _error = null;
    });
    try {
      final api = widget.state.api!;
      final List<Release> releases;
      if (widget.state.type == ServerType.radarr) {
        releases = await api.getReleases(movieId: widget.item.id);
      } else if (widget.episodeId != null) {
        releases = await api.getReleases(episodeId: widget.episodeId);
      } else {
        releases = await api.getReleases(
          seriesId: widget.item.id,
          seasonNumber: widget.seasonNumber,
        );
      }
      if (mounted) setState(() => _releases = releases);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String get _subtitle {
    if (widget.episodeLabel != null) {
      return '${widget.item.title} — ${widget.episodeLabel}';
    }
    if (widget.seasonNumber != null) {
      return '${widget.item.title} — ${widget.seasonNumber == 0 ? "Specials" : "Season ${widget.seasonNumber}"}';
    }
    return widget.item.title;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Releases'),
            Text(
              _subtitle,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (_releases != null || _error != null)
            IconButton(icon: const Icon(Icons.refresh), onPressed: _search),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (_error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Search failed: $_error', textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _search, child: const Text('Retry')),
                  ],
                ),
              ),
            );
          }
          if (_releases == null) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Searching indexers...\nThis can take a minute.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          if (_releases!.isEmpty) {
            return const Center(child: Text('No releases found'));
          }
          return ListView.separated(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewPadding.bottom,
            ),
            itemCount: _releases!.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => _ReleaseTile(
              release: _releases![i],
              onGrab: () => _confirmGrab(_releases![i]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmGrab(Release release) async {
    final grabbed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _GrabSheet(state: widget.state, release: release),
    );
    if (grabbed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Release sent to download client')),
      );
      Navigator.of(context).pop();
    }
  }
}

class _ReleaseTile extends StatelessWidget {
  final Release release;
  final VoidCallback onGrab;

  const _ReleaseTile({required this.release, required this.onGrab});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
    );
    return ListTile(
      onTap: onGrab,
      leading: Icon(
        release.rejected
            ? Icons.warning_amber
            : release.isTorrent
            ? Icons.swap_vert
            : Icons.rss_feed,
        color: release.rejected ? Colors.amber : theme.colorScheme.primary,
      ),
      title: Text(
        release.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 10,
          runSpacing: 2,
          children: [
            Text(
              release.quality,
              style: muted?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(release.sizeLabel, style: muted),
            Text(release.ageLabel, style: muted),
            Text(release.indexer, style: muted),
            if (release.isTorrent)
              Text(
                'S:${release.seeders ?? "?"} L:${release.leechers ?? "?"}',
                style: muted,
              ),
            if (release.fullSeason) Text('Season pack', style: muted),
          ],
        ),
      ),
    );
  }
}

class _GrabSheet extends StatefulWidget {
  final ServiceState state;
  final Release release;

  const _GrabSheet({required this.state, required this.release});

  @override
  State<_GrabSheet> createState() => _GrabSheetState();
}

class _GrabSheetState extends State<_GrabSheet> {
  bool _grabbing = false;
  String? _error;

  Future<void> _grab() async {
    setState(() {
      _grabbing = true;
      _error = null;
    });
    try {
      await widget.state.api!.grabRelease(widget.release);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _grabbing = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.release;
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          top: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(
              '${r.quality} • ${r.sizeLabel} • ${r.ageLabel} old • ${r.indexer}'
              '${r.isTorrent ? " • ${r.seeders ?? "?"} seeders" : ""}',
              style: theme.textTheme.bodySmall,
            ),
            if (r.rejections.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Rejected by ${widget.state.type == ServerType.radarr ? "Radarr" : "Sonarr"}:',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.amber),
              ),
              for (final reason in r.rejections)
                Text(
                  '• $reason',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.amber,
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                'You can still download it — the server will be told to grab this release anyway.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _grabbing ? null : _grab,
                icon: _grabbing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download),
                label: Text(_grabbing ? 'Sending...' : 'Download this release'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
