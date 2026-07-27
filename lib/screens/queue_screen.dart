import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/queue_item.dart';
import '../state/app_state.dart';
import '../widgets/poster.dart';

/// Combined Radarr + Sonarr download queue with live progress and
/// remove/blocklist actions.
class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  List<QueueItem>? _movieQueue;
  List<QueueItem>? _tvQueue;
  String? _movieError;
  String? _tvError;
  bool _refreshing = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Progress moves constantly while downloads run; poll while the app
    // is open. LAN-only calls, so this is cheap.
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;
    final radarr = context.read<RadarrState>();
    final sonarr = context.read<SonarrState>();
    try {
      if (radarr.api != null) {
        try {
          _movieQueue = await radarr.api!.getQueue();
          _movieError = null;
        } catch (e) {
          _movieError = e.toString();
        }
      }
      if (sonarr.api != null) {
        try {
          _tvQueue = await sonarr.api!.getQueue();
          _tvError = null;
        } catch (e) {
          _tvError = e.toString();
        }
      }
    } finally {
      _refreshing = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _remove(ServiceState service, QueueItem item) async {
    var removeFromClient = true;
    var blocklist = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Remove "${item.mediaTitle}"?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Remove from download client'),
                value: removeFromClient,
                onChanged: (v) => setDialogState(() => removeFromClient = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Blocklist this release'),
                subtitle: const Text('Prevents it being grabbed again'),
                value: blocklist,
                onChanged: (v) => setDialogState(() => blocklist = v),
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
              child: const Text('Remove'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await service.api!.deleteQueueItem(
        item.id,
        removeFromClient: removeFromClient,
        blocklist: blocklist,
      );
      await _refresh();
      unawaited(service.refreshLibrary());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed "${item.mediaTitle}" from queue')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Remove failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final radarr = context.watch<RadarrState>();
    final sonarr = context.watch<SonarrState>();
    final theme = Theme.of(context);

    if (!radarr.isConfigured && !sonarr.isConfigured) {
      return const Center(
          child: Text('Set up your servers in the Settings tab first.'));
    }

    final movieQueue = _movieQueue ?? [];
    final tvQueue = _tvQueue ?? [];
    final loading = _movieQueue == null && _tvQueue == null;
    final empty = movieQueue.isEmpty &&
        tvQueue.isEmpty &&
        _movieError == null &&
        _tvError == null;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : empty
              ? LayoutBuilder(
                  builder: (context, constraints) => ListView(
                    children: [
                      SizedBox(
                        height: constraints.maxHeight,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.download_done,
                                  size: 48,
                                  color: theme.colorScheme.outline),
                              const SizedBox(height: 16),
                              const Text('Queue is empty'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView(
                  children: [
                    if (movieQueue.isNotEmpty || _movieError != null)
                      _sectionHeader(
                          context, 'Movies', movieQueue.length),
                    if (_movieError != null)
                      _errorRow(context, _movieError!),
                    for (final item in movieQueue)
                      _QueueTile(
                        item: item,
                        onRemove: () => _remove(radarr, item),
                      ),
                    if (tvQueue.isNotEmpty || _tvError != null)
                      _sectionHeader(context, 'TV Shows', tvQueue.length),
                    if (_tvError != null) _errorRow(context, _tvError!),
                    for (final item in tvQueue)
                      _QueueTile(
                        item: item,
                        onRemove: () => _remove(sonarr, item),
                      ),
                    SizedBox(
                      height: 24 + MediaQuery.of(context).viewPadding.bottom,
                    ),
                  ],
                ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title, int count) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          '$title ($count)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );

  Widget _errorRow(BuildContext context, String error) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          'Could not load queue: $error',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
}

class _QueueTile extends StatelessWidget {
  final QueueItem item;
  final VoidCallback onRemove;

  const _QueueTile({required this.item, required this.onRemove});

  Color _statusColor(BuildContext context) => switch (item.statusLabel) {
        'Downloading' => Colors.lightBlue,
        'Importing' || 'Completed' => Colors.green,
        'Paused' => Colors.amber,
        'Failed' || 'Warning' => Theme.of(context).colorScheme.error,
        _ => Theme.of(context).colorScheme.outline,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7));
    final statusColor = _statusColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Poster(url: item.posterUrl, width: 45),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.episodeLabel == null
                      ? item.mediaTitle
                      : '${item.mediaTitle} — ${item.episodeLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  item.releaseTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: item.progress,
                    minHeight: 6,
                    color: statusColor,
                    backgroundColor:
                        theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  children: [
                    Text(item.statusLabel,
                        style: muted?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w600)),
                    Text('${(item.progress * 100).toStringAsFixed(0)}%',
                        style: muted),
                    Text(item.sizeLabel, style: muted),
                    if (item.timeleft != null)
                      Text(item.timeleft!, style: muted),
                  ],
                ),
                if (item.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      item.errorMessage!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
