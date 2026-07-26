import 'package:flutter/material.dart';

import '../services/update_service.dart';

/// Opens the download-and-install flow for a known-available [update] in a modal
/// bottom sheet. Shared by the launch-time "update available" prompt and the
/// Settings → App updates card, so both use the identical notify → download →
/// install path (never silent, mirroring the desktop app's UX).
Future<void> showAppUpdateSheet(BuildContext context, AppUpdate update) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _UpdateSheet(update: update),
  );
}

class _UpdateSheet extends StatefulWidget {
  final AppUpdate update;
  const _UpdateSheet({required this.update});

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> {
  double? _progress; // null = not started or indeterminate
  bool _downloading = false;
  String? _apkPath;
  String? _error;

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _error = null;
      _progress = null;
    });
    try {
      final path = await UpdateService.downloadApk(
        widget.update,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _apkPath = path;
        _downloading = false;
      });
      // Straight into the system installer once the download lands.
      await _install();
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _install() async {
    if (_apkPath == null) return;
    try {
      await UpdateService.installApk(_apkPath!);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final u = widget.update;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Update available', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Version ${u.version} — you have ${u.currentVersion}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            if (u.notes.isNotEmpty) ...[
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Text(u.notes, style: theme.textTheme.bodyMedium),
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 12),
            ],
            if (_downloading)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 8),
                  Text(
                    _progress == null
                        ? 'Downloading…'
                        : 'Downloading… ${(_progress! * 100).toStringAsFixed(0)}%',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _apkPath == null ? _download : _install,
                  icon: Icon(_apkPath == null
                      ? Icons.download
                      : Icons.install_mobile),
                  label: Text(_apkPath == null
                      ? 'Download & install'
                      : 'Install'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Settings card: checks for an update on demand and, when one exists, opens the
/// download/install sheet. Auto-checks once when the page opens.
class AppUpdateCard extends StatefulWidget {
  const AppUpdateCard({super.key});

  @override
  State<AppUpdateCard> createState() => _AppUpdateCardState();
}

enum _CheckState { checking, upToDate, available, error }

class _AppUpdateCardState extends State<AppUpdateCard> {
  _CheckState _state = _CheckState.checking;
  AppUpdate? _update;
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _state = _CheckState.checking;
      _error = null;
    });
    try {
      final update = await UpdateService.checkForUpdate();
      if (!mounted) return;
      setState(() {
        _update = update;
        _state =
            update == null ? _CheckState.upToDate : _CheckState.available;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _CheckState.error;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.system_update, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    switch (_state) {
                      _CheckState.checking => 'Checking for updates…',
                      _CheckState.upToDate => 'ArrHub is up to date',
                      _CheckState.available =>
                        'Update available: ${_update!.version}',
                      _CheckState.error => 'Couldn\'t check for updates',
                    },
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (_state == _CheckState.checking)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (_state == _CheckState.error && _error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            if (_state == _CheckState.available)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => showAppUpdateSheet(context, _update!),
                  icon: const Icon(Icons.download),
                  label: Text('Update to ${_update!.version}'),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed:
                      _state == _CheckState.checking ? null : _check,
                  child: const Text('Check again'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
