import 'dart:async';

import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../models/server_config.dart';
import '../state/app_state.dart';
import '../widgets/poster.dart';

/// Search TMDB/TVDB (via the server's lookup endpoint) and add new items.
class AddSearchScreen extends StatefulWidget {
  final ServiceState state;
  const AddSearchScreen({super.key, required this.state});

  @override
  State<AddSearchScreen> createState() => _AddSearchScreenState();
}

class _AddSearchScreenState extends State<AddSearchScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<MediaItem> _results = [];
  bool _searching = false;
  String? _error;

  bool get _isRadarr => widget.state.type == ServerType.radarr;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => _search(query));
  }

  Future<void> _search(String query) async {
    query = query.trim();
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await widget.state.api!.lookup(query);
      if (!mounted) return;
      setState(() => _results = results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  /// tmdb/tvdb ids of items already in the library.
  Set<int> get _libraryIds =>
      widget.state.library.map((m) => m.externalId).toSet();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          onChanged: _onQueryChanged,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: _isRadarr
                ? 'Search for a movie...'
                : 'Search for a show...',
            border: InputBorder.none,
          ),
        ),
      ),
      body: Builder(
        builder: (context) {
          if (_searching) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Search failed: $_error',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (_results.isEmpty) {
            return Center(
              child: Text(
                _searchController.text.isEmpty
                    ? 'Type to search'
                    : 'No results',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            );
          }
          final libraryIds = _libraryIds;
          return ListView.builder(
            itemCount: _results.length,
            itemBuilder: (context, i) {
              final item = _results[i];
              final inLibrary =
                  item.inLibrary || libraryIds.contains(item.externalId);
              return InkWell(
                onTap: inLibrary
                    ? null
                    : () async {
                        final added = await showModalBottomSheet<bool>(
                          context: context,
                          isScrollControlled: true,
                          showDragHandle: true,
                          builder: (_) =>
                              AddSheet(state: widget.state, item: item),
                        );
                        if (added == true && context.mounted) {
                          setState(() {}); // refresh in-library checkmarks
                        }
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Poster(url: item.posterUrl, width: 60),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (item.year != null && item.year != 0)
                              Text(
                                '${item.year}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            if (item.overview.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                item.overview,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: inLibrary
                            ? const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              )
                            : const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class AddSheet extends StatefulWidget {
  final ServiceState state;
  final MediaItem item;
  const AddSheet({super.key, required this.state, required this.item});

  @override
  State<AddSheet> createState() => AddSheetState();
}

class AddSheetState extends State<AddSheet> {
  List<QualityProfile>? _profiles;
  List<RootFolder>? _rootFolders;
  List<DiskSpace> _disks = [];
  int? _profileId;
  String? _rootFolder;
  bool _searchNow = true;
  bool _adding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final api = widget.state.api!;
      final profiles = await api.getQualityProfiles();
      final folders = await api.getRootFolders();
      List<DiskSpace> disks = [];
      try {
        disks = await api.getDiskSpace();
      } catch (_) {} // warning is best-effort only
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _rootFolders = folders;
        _disks = disks;
        _profileId = profiles.isNotEmpty ? profiles.first.id : null;
        _rootFolder = folders.isNotEmpty ? folders.first.path : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load options: $e');
    }
  }

  /// Disk hosting the selected root folder (longest path prefix wins).
  DiskSpace? get _selectedDisk {
    final folder = _rootFolder?.toLowerCase();
    if (folder == null) return null;
    DiskSpace? best;
    for (final disk in _disks) {
      final diskPath = disk.path.toLowerCase();
      if (folder.startsWith(diskPath) &&
          (best == null || diskPath.length > best.path.length)) {
        best = disk;
      }
    }
    return best;
  }

  Future<void> _add() async {
    if (_profileId == null || _rootFolder == null) return;
    setState(() {
      _adding = true;
      _error = null;
    });
    try {
      await widget.state.api!.add(
        item: widget.item,
        qualityProfileId: _profileId!,
        rootFolderPath: _rootFolder!,
        searchNow: _searchNow,
      );
      unawaited(widget.state.refreshLibrary());
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Added "${widget.item.title}"')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _adding = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = _profiles == null && _error == null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Poster(url: widget.item.posterUrl, width: 60),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (widget.item.year != null) Text('${widget.item.year}'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (loading)
              const Center(child: CircularProgressIndicator())
            else if (_profiles != null) ...[
              DropdownButtonFormField<int>(
                initialValue: _profileId,
                decoration: const InputDecoration(
                  labelText: 'Quality Profile',
                  border: OutlineInputBorder(),
                ),
                items: _profiles!
                    .map(
                      (p) => DropdownMenuItem(value: p.id, child: Text(p.name)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _profileId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _rootFolder,
                decoration: const InputDecoration(
                  labelText: 'Root Folder',
                  border: OutlineInputBorder(),
                ),
                items: _rootFolders!
                    .map(
                      (f) =>
                          DropdownMenuItem(value: f.path, child: Text(f.path)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _rootFolder = v),
              ),
              if (_selectedDisk != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (_selectedDisk!.usedFraction > 0.9) ...[
                      const Icon(Icons.warning_amber,
                          size: 16, color: Colors.amber),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      '${_selectedDisk!.freeLabel} free of '
                      '${_selectedDisk!.totalLabel} on this drive',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _selectedDisk!.usedFraction > 0.9
                                ? Colors.amber
                                : null,
                          ),
                    ),
                  ],
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Search for download now'),
                value: _searchNow,
                onChanged: (v) => setState(() => _searchNow = v),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    (_adding || _profileId == null || _rootFolder == null)
                    ? null
                    : _add,
                icon: _adding
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                label: Text(_adding ? 'Adding...' : 'Add'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
