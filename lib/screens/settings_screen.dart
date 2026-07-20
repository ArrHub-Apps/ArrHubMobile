import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/arr_api.dart';
import '../api/tmdb_api.dart';
import '../main.dart';
import '../models/media_item.dart';
import '../models/server_config.dart';
import '../services/notification_service.dart';
import '../services/settings_store.dart';
import '../state/app_state.dart';
import '../widgets/poster.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: const [
        _SettingsMenuTile(
          icon: Icons.dns_outlined,
          title: 'Servers',
          subtitle: 'Radarr & Sonarr connections',
          pageTitle: 'Servers',
          cards: [
            _ServerConfigCard(type: ServerType.radarr),
            SizedBox(height: 16),
            _ServerConfigCard(type: ServerType.sonarr),
          ],
        ),
        _SettingsMenuTile(
          icon: Icons.explore_outlined,
          title: 'Discover',
          subtitle: 'TMDB API key',
          pageTitle: 'Discover',
          cards: [_TmdbCard()],
        ),
        _SettingsMenuTile(
          icon: Icons.notifications_outlined,
          title: 'Notifications',
          subtitle: 'Download-complete alerts',
          pageTitle: 'Notifications',
          cards: [_NotificationsCard()],
        ),
        _SettingsMenuTile(
          icon: Icons.palette_outlined,
          title: 'Appearance',
          subtitle: 'Theme & accent color',
          pageTitle: 'Appearance',
          cards: [_AppearanceCard()],
        ),
        _SettingsMenuTile(
          icon: Icons.storage_outlined,
          title: 'Storage',
          subtitle: 'Disk space, library sizes & cleanup',
          pageTitle: 'Storage',
          cards: [_StorageCard(), SizedBox(height: 16), _CleanupCard()],
        ),
      ],
    );
  }
}

class _SettingsMenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String pageTitle;
  final List<Widget> cards;

  const _SettingsMenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.pageTitle,
    required this.cards,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(pageTitle)),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: cards,
            ),
          ),
        ),
      ),
    );
  }
}

/// Flags old downloaded items as cleanup candidates, biggest first.
class _CleanupCard extends StatefulWidget {
  const _CleanupCard();

  @override
  State<_CleanupCard> createState() => _CleanupCardState();
}

class _CleanupCardState extends State<_CleanupCard> {
  static const _monthsPrefKey = 'cleanup_months';
  static const _maxRows = 15;
  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  int _months = 6;
  final Set<String> _selected = {};
  bool _deleting = false;
  int _deleteProgress = 0;
  int _deleteTotal = 0;

  static String _keyFor(ServiceState service, MediaItem item) =>
      '${service.type.name}:${item.id}';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getInt(_monthsPrefKey);
      if (saved != null && mounted) setState(() => _months = saved);
    });
  }

  void _setMonths(int months) {
    setState(() => _months = months);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setInt(_monthsPrefKey, months));
  }

  static String _fmtBytes(int bytes) {
    final tb = bytes / (1024 * 1024 * 1024 * 1024);
    if (tb >= 1) return '${tb.toStringAsFixed(2)} TB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _batchDelete(
      List<(ServiceState, MediaItem)> targets) async {
    final totalBytes =
        targets.fold<int>(0, (sum, t) => sum + t.$2.sizeOnDisk);
    var deleteFiles = true; // cleanup context: freeing space is the point
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(
              'Delete ${targets.length} item${targets.length == 1 ? "" : "s"}?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'This removes them from your library. They can be re-added later.'),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Also delete files from disk'),
                subtitle: deleteFiles
                    ? Text(
                        '${_fmtBytes(totalBytes)} will be permanently deleted',
                        style: TextStyle(
                            color:
                                Theme.of(dialogContext).colorScheme.error),
                      )
                    : Text('${_fmtBytes(totalBytes)} on disk'),
                value: deleteFiles,
                onChanged: (v) => setDialogState(() => deleteFiles = v),
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
    if (confirmed != true || !mounted) return;

    setState(() {
      _deleting = true;
      _deleteProgress = 0;
      _deleteTotal = targets.length;
    });
    var freedBytes = 0;
    var failures = 0;
    final touchedServices = <ServiceState>{};
    for (final (service, item) in targets) {
      try {
        await service.api!.deleteItem(item.id!, deleteFiles: deleteFiles);
        freedBytes += item.sizeOnDisk;
        touchedServices.add(service);
      } catch (_) {
        failures++;
      }
      if (mounted) setState(() => _deleteProgress++);
    }
    for (final service in touchedServices) {
      unawaited(service.refreshLibrary());
    }
    if (!mounted) return;
    setState(() {
      _deleting = false;
      _selected.clear();
    });
    final freedLabel = deleteFiles ? ' — freed ${_fmtBytes(freedBytes)}' : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(failures == 0
            ? 'Deleted ${targets.length - failures} items$freedLabel'
            : 'Deleted ${targets.length - failures} items$freedLabel '
                '($failures failed)'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radarr = context.watch<RadarrState>();
    final sonarr = context.watch<SonarrState>();
    final cutoff =
        DateTime.now().subtract(Duration(days: _months * 30));

    final entries = <(ServiceState, MediaItem)>[
      for (final m in radarr.library) (radarr, m),
      for (final s in sonarr.library) (sonarr, s),
    ]
        .where((e) =>
            e.$2.sizeOnDisk > 0 &&
            e.$2.added != null &&
            e.$2.added!.isBefore(cutoff))
        .toList()
      ..sort((a, b) => b.$2.sizeOnDisk.compareTo(a.$2.sizeOnDisk));
    final totalBytes =
        entries.fold<int>(0, (sum, e) => sum + e.$2.sizeOnDisk);
    final visible = entries.take(_maxRows).toList();
    final hiddenCount = entries.length - visible.length;
    final hiddenBytes = entries
        .skip(_maxRows)
        .fold<int>(0, (sum, e) => sum + e.$2.sizeOnDisk);

    // Drop selections that no longer exist (deleted or threshold change).
    final validKeys = {for (final e in entries) _keyFor(e.$1, e.$2)};
    _selected.retainAll(validKeys);
    final selectedEntries = [
      for (final e in entries)
        if (_selected.contains(_keyFor(e.$1, e.$2))) e
    ];
    final selectedBytes =
        selectedEntries.fold<int>(0, (sum, e) => sum + e.$2.sizeOnDisk);
    final allVisibleSelected = visible.isNotEmpty &&
        visible.every((e) => _selected.contains(_keyFor(e.$1, e.$2)));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_delete_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Suggested cleanup',
                    style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 3, label: Text('3 mo')),
                  ButtonSegment(value: 6, label: Text('6 mo')),
                  ButtonSegment(value: 12, label: Text('12 mo')),
                ],
                showSelectedIcon: false,
                selected: {_months},
                onSelectionChanged: (s) => _setMonths(s.first),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              entries.isEmpty
                  ? 'Nothing downloaded more than $_months months ago — all tidy.'
                  : '${entries.length} item${entries.length == 1 ? "" : "s"} added over '
                      '$_months months ago — ${_fmtBytes(totalBytes)} reclaimable',
              style: theme.textTheme.bodyMedium,
            ),
            if (entries.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  TextButton(
                    onPressed: _deleting
                        ? null
                        : () => setState(() {
                              if (allVisibleSelected) {
                                _selected.clear();
                              } else {
                                for (final (s, i) in visible) {
                                  _selected.add(_keyFor(s, i));
                                }
                              }
                            }),
                    child: Text(
                        allVisibleSelected ? 'Clear all' : 'Select all'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD32F2F),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: (_deleting || selectedEntries.isEmpty)
                        ? null
                        : () => _batchDelete(selectedEntries),
                    icon: _deleting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline),
                    label: Text(_deleting
                        ? 'Deleting $_deleteProgress/$_deleteTotal...'
                        : selectedEntries.isEmpty
                            ? 'Delete'
                            : 'Delete ${selectedEntries.length} '
                                '(${_fmtBytes(selectedBytes)})'),
                  ),
                ],
              ),
            ],
            for (final (service, item) in visible)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                enabled: !_deleting,
                onTap: () => setState(() {
                  final key = _keyFor(service, item);
                  if (!_selected.remove(key)) _selected.add(key);
                }),
                leading: Poster(url: item.posterUrl, width: 34),
                title: Text(item.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  'Added ${_monthNames[item.added!.month - 1]} ${item.added!.year}'
                  ' • ${item.sizeLabel}',
                ),
                trailing: Checkbox(
                  value: _selected.contains(_keyFor(service, item)),
                  onChanged: _deleting
                      ? null
                      : (v) => setState(() {
                            final key = _keyFor(service, item);
                            if (v == true) {
                              _selected.add(key);
                            } else {
                              _selected.remove(key);
                            }
                          }),
                ),
              ),
            if (hiddenCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '+ $hiddenCount more (${_fmtBytes(hiddenBytes)}) — delete some above to see them',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Theme mode selector + accent color swatches.
class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  static const _accents = [
    Color(0xFF1DB954), // spotify green (default)
    Color(0xFF00BFA5), // teal
    Color(0xFF00BCD4), // cyan
    Color(0xFF2196F3), // blue
    Color(0xFF7C4DFF), // purple
    Color(0xFFE040FB), // magenta
    Color(0xFFEC407A), // pink
    Color(0xFFF44336), // red
    Color(0xFFFF9800), // orange
    Color(0xFFFFC107), // amber
  ];

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.palette_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Appearance', style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                      value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ButtonSegment(
                      value: ThemeMode.system, label: Text('System')),
                ],
                showSelectedIcon: false,
                selected: {themeState.mode},
                onSelectionChanged: (s) => themeState.setMode(s.first),
              ),
            ),
            const SizedBox(height: 16),
            Text('Accent color', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final color in _accents)
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => themeState.setAccent(color),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: themeState.accent.toARGB32() ==
                                  color.toARGB32()
                              ? theme.colorScheme.onSurface
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: themeState.accent.toARGB32() ==
                              color.toARGB32()
                          ? Icon(
                              Icons.check,
                              size: 20,
                              color: color.computeLuminance() > 0.4
                                  ? Colors.black
                                  : Colors.white,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Toggle for background download-complete notifications.
class _NotificationsCard extends StatefulWidget {
  const _NotificationsCard();

  @override
  State<_NotificationsCard> createState() => _NotificationsCardState();
}

class _NotificationsCardState extends State<_NotificationsCard> {
  final _store = SettingsStore();
  bool _enabled = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _store.loadNotificationsEnabled().then((enabled) {
      if (mounted) {
        setState(() {
          _enabled = enabled;
          _loaded = true;
        });
      }
    });
  }

  Future<void> _toggle(bool enabled) async {
    if (enabled) {
      final granted = await NotificationService.requestPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Notification permission denied — enable it in Android settings')),
          );
        }
        return;
      }
    }
    await _store.saveNotificationsEnabled(enabled);
    await configureBackgroundChecks(enabled);
    if (enabled) {
      // Baseline now so only future completions notify.
      unawaited(NotificationService.checkForCompletedDownloads());
    }
    if (mounted) setState(() => _enabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SwitchListTile(
          secondary: Icon(Icons.notifications_outlined,
              color: Theme.of(context).colorScheme.primary),
          title: const Text('Download notifications'),
          subtitle: const Text(
              'Notify when a download finishes importing (checks ~every 15 min)'),
          value: _enabled,
          onChanged: _loaded ? _toggle : null,
        ),
      ),
    );
  }
}

/// TMDB API key for the Discover tab.
class _TmdbCard extends StatefulWidget {
  const _TmdbCard();

  @override
  State<_TmdbCard> createState() => _TmdbCardState();
}

class _TmdbCardState extends State<_TmdbCard> {
  final _keyController = TextEditingController();
  bool _obscure = true;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;
  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_seeded) {
      final key = context.watch<TmdbState>().apiKey;
      if (key != null && key.isNotEmpty) {
        if (_keyController.text.isEmpty) _keyController.text = key;
        _seeded = true;
      }
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final api = TmdbApi(_keyController.text.trim());
    try {
      await api.test();
      setState(() {
        _testOk = true;
        _testResult = 'Connected to TMDB';
      });
    } catch (e) {
      setState(() {
        _testOk = false;
        _testResult = 'Failed: $e';
      });
    } finally {
      api.dispose();
      setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    await context.read<TmdbState>().updateApiKey(_keyController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('TMDB settings saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.explore_outlined,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('Discover (TMDB)',
                    style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _keyController,
              obscureText: _obscure,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'TMDB API Key',
                helperText:
                    'Free at themoviedb.org — Settings > API (v3 key)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 12),
              Text(
                _testResult!,
                style: TextStyle(
                  color: _testOk
                      ? Colors.green
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _testing ? null : _test,
                  child: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Test'),
                ),
                const SizedBox(width: 12),
                FilledButton(onPressed: _save, child: const Text('Save')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Free space for the drives hosting the servers' root folders (merged
/// across Radarr and Sonarr — they often share a drive).
class _StorageCard extends StatefulWidget {
  const _StorageCard();

  @override
  State<_StorageCard> createState() => _StorageCardState();
}

class _StorageCardState extends State<_StorageCard> {
  List<DiskSpace>? _disks;
  String? _error;
  bool _loading = false;
  String _loadedForConfigs = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final radarr = context.watch<RadarrState>();
    final sonarr = context.watch<SonarrState>();
    // Reload when the set of configured servers changes.
    final configKey =
        '${radarr.config?.encode() ?? ""}|${sonarr.config?.encode() ?? ""}';
    if (configKey != _loadedForConfigs) {
      _loadedForConfigs = configKey;
      _load(radarr, sonarr);
    }
  }

  Future<void> _load(RadarrState radarr, SonarrState sonarr) async {
    final services = [radarr, sonarr].where((s) => s.api != null).toList();
    if (services.isEmpty) {
      setState(() {
        _disks = null;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final byDrive = <String, DiskSpace>{};
      for (final service in services) {
        for (final disk in await service.api!.getRootFolderDiskSpace()) {
          byDrive[disk.path.toLowerCase()] = disk;
        }
      }
      final disks = byDrive.values.toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      if (mounted) setState(() => _disks = disks);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_disks == null && _error == null && !_loading) {
      return const SizedBox.shrink(); // no servers configured yet
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storage_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Storage', style: theme.textTheme.titleLarge),
                const Spacer(),
                if (_loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: () => _load(
                      context.read<RadarrState>(),
                      context.read<SonarrState>(),
                    ),
                  ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Could not load disk space: $_error',
                    style: TextStyle(color: theme.colorScheme.error)),
              )
            else
              for (final disk in _disks ?? <DiskSpace>[])
                _DiskRow(disk: disk),
            const _LibrarySizeRows(),
          ],
        ),
      ),
    );
  }
}

/// How much of the disk each library accounts for, summed from the
/// already-loaded libraries (no extra API calls).
class _LibrarySizeRows extends StatelessWidget {
  const _LibrarySizeRows();

  static String _fmt(int bytes) {
    final tb = bytes / (1024 * 1024 * 1024 * 1024);
    if (tb >= 1) return '${tb.toStringAsFixed(2)} TB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radarr = context.watch<RadarrState>();
    final sonarr = context.watch<SonarrState>();
    final rows = <(IconData, String, int, int)>[
      if (radarr.library.isNotEmpty)
        (
          Icons.movie_outlined,
          'Movies library',
          radarr.library.fold(0, (sum, m) => sum + m.sizeOnDisk),
          radarr.library.length,
        ),
      if (sonarr.library.isNotEmpty)
        (
          Icons.tv_outlined,
          'TV library',
          sonarr.library.fold(0, (sum, s) => sum + s.sizeOnDisk),
          sonarr.library.length,
        ),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          for (final (icon, label, bytes, count) in rows)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: theme.colorScheme.outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('$label ($count titles)',
                        style: theme.textTheme.bodySmall),
                  ),
                  Text(_fmt(bytes), style: theme.textTheme.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DiskRow extends StatelessWidget {
  final DiskSpace disk;
  const _DiskRow({required this.disk});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nearlyFull = disk.usedFraction > 0.9;
    final barColor =
        nearlyFull ? Colors.amber : theme.colorScheme.primary;
    final name =
        disk.label.isEmpty ? disk.path : '${disk.path} (${disk.label})';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name, style: theme.textTheme.bodyMedium),
              ),
              Text(
                '${disk.freeLabel} free of ${disk.totalLabel}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: disk.usedFraction,
              minHeight: 8,
              color: barColor,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerConfigCard extends StatefulWidget {
  final ServerType type;
  const _ServerConfigCard({required this.type});

  @override
  State<_ServerConfigCard> createState() => _ServerConfigCardState();
}

class _ServerConfigCardState extends State<_ServerConfigCard> {
  final _urlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _obscureKey = true;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;
  bool _seeded = false;

  String get _label => widget.type == ServerType.radarr ? 'Radarr' : 'Sonarr';

  ServiceState _state(BuildContext context, {bool listen = false}) =>
      widget.type == ServerType.radarr
          ? Provider.of<RadarrState>(context, listen: listen)
          : Provider.of<SonarrState>(context, listen: listen);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Config loads asynchronously at startup; keep trying to seed the
    // fields (listen: true re-triggers this) until it arrives, unless the
    // user has already started typing.
    if (!_seeded) {
      final config = _state(context, listen: true).config;
      if (config != null) {
        if (_urlController.text.isEmpty && _apiKeyController.text.isEmpty) {
          _urlController.text = config.baseUrl;
          _apiKeyController.text = config.apiKey;
        }
        _seeded = true;
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  ServerConfig get _draft => ServerConfig(
        type: widget.type,
        baseUrl: _urlController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
      );

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final api = ArrApi(_draft);
    try {
      final version = await api.testConnection();
      setState(() {
        _testOk = true;
        _testResult = 'Connected — $_label $version';
      });
    } catch (e) {
      setState(() {
        _testOk = false;
        _testResult = 'Failed: $e';
      });
    } finally {
      api.dispose();
      setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    await _state(context).updateConfig(_draft);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$_label settings saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  widget.type == ServerType.radarr
                      ? Icons.movie_outlined
                      : Icons.tv_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(_label, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Server URL',
                hintText: 'http://192.168.1.10:${widget.type == ServerType.radarr ? 7878 : 8989}',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyController,
              obscureText: _obscureKey,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'API Key',
                helperText: 'Settings > General > API Key in $_label',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscureKey ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 12),
              Text(
                _testResult!,
                style: TextStyle(
                  color: _testOk
                      ? Colors.green
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _testing ? null : _test,
                  child: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Test'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _save,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
