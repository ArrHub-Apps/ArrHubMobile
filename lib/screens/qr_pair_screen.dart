import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../models/server_config.dart';
import '../services/pairing_service.dart';
import '../state/app_state.dart';

/// Scans the pairing QR shown by the desktop app (Settings → Sharing), claims the code,
/// and configures both Radarr and Sonarr automatically — including the remote HTTPS
/// address when the host has remote access set up.
class QrPairScreen extends StatefulWidget {
  const QrPairScreen({super.key});

  @override
  State<QrPairScreen> createState() => _QrPairScreenState();
}

class _QrPairScreenState extends State<QrPairScreen> {
  final _controller = MobileScannerController();
  bool _handling = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Pulls the first non-empty raw string out of a scan/analyze result.
  String? _rawFrom(BarcodeCapture? capture) => capture?.barcodes
      .map((b) => b.rawValue)
      .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);

  /// Parses our pairing QR payload (JSON `{host, port, code}`). Null if it isn't one
  /// of ours — shared by the live scanner and the scan-from-photo path.
  ({String host, int port, String code})? _parsePayload(String raw) {
    try {
      final payload = jsonDecode(raw) as Map<String, dynamic>;
      final host = payload['host'] as String?;
      final port = payload['port'];
      final code = payload['code'] as String?;
      if (host == null || code == null || port is! int) return null;
      return (host: host, port: port, code: code);
    } catch (_) {
      return null;
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final raw = _rawFrom(capture);
    if (raw == null) return;
    final parsed = _parsePayload(raw);
    if (parsed == null) return; // not one of our QR codes — keep scanning

    setState(() {
      _handling = true;
      _error = null;
    });
    await _controller.stop();
    await _claim(parsed.host, parsed.port, parsed.code);
  }

  /// Camera-free path: decode the pairing QR from a saved image (e.g. a screenshot of
  /// the desktop QR). Essential on the iOS Simulator, which has no camera at all.
  Future<void> _scanFromPhoto() async {
    if (_handling) return;
    final XFile? file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;

    setState(() {
      _handling = true;
      _error = null;
    });
    await _controller.stop();
    try {
      final capture = await _controller.analyzeImage(file.path);
      final raw = _rawFrom(capture);
      final parsed = raw == null ? null : _parsePayload(raw);
      if (parsed == null) {
        _fail("That image doesn't contain an ArrHub pairing QR code.");
        return;
      }
      await _claim(parsed.host, parsed.port, parsed.code);
    } catch (e) {
      _fail('Could not read that image: $e');
    }
  }

  Future<void> _claim(String host, int port, String code) async {
    final radarrState = context.read<RadarrState>();
    final sonarrState = context.read<SonarrState>();
    final tmdbState = context.read<TmdbState>();
    final navigator = Navigator.of(context);
    try {
      final bundle = await PairingService.claim(host, port, code);
      await radarrState.updateConfig(bundle.configFor(ServerType.radarr));
      await sonarrState.updateConfig(bundle.configFor(ServerType.sonarr));
      // Adopt the host's shared TMDB key only if this phone hasn't set its own — never
      // clobber a key the user entered manually.
      final tmdbShared = bundle.tmdbApiKey.isNotEmpty && !tmdbState.isConfigured;
      if (tmdbShared) await tmdbState.updateApiKey(bundle.tmdbApiKey);
      if (!mounted) return;
      final remote = bundle.certFingerprint.isNotEmpty;
      final discover = tmdbShared ? ' Discover is ready too.' : '';
      navigator.pop(
        (remote
                ? 'Paired — Radarr & Sonarr configured, with remote access for when you’re away.'
                : 'Paired — Radarr & Sonarr configured.') +
            discover,
      );
    } on PairingException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('Pairing failed: $e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _handling = false;
      _error = message;
    });
    _controller.start();
  }

  Future<void> _manualEntry() async {
    final hostController = TextEditingController();
    final codeController = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter code manually'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: hostController,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Host',
                hintText: '192.168.1.10:47100',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeController,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Pairing code',
                hintText: '6 characters',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Pair')),
        ],
      ),
    );
    if (submitted != true) return;

    var host = hostController.text.trim();
    var port = 47100;
    final match = RegExp(r'^(.+):(\d+)$').firstMatch(host);
    if (match != null) {
      host = match.group(1)!;
      port = int.tryParse(match.group(2)!) ?? 47100;
    }
    final code = codeController.text.trim().toUpperCase();
    if (host.isEmpty || code.isEmpty) return;

    setState(() {
      _handling = true;
      _error = null;
    });
    await _controller.stop();
    await _claim(host, port, code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair with desktop'),
        actions: [
          IconButton(
            tooltip: 'Scan from photo',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: _handling ? null : _scanFromPhoto,
          ),
          IconButton(
            tooltip: 'Enter code manually',
            icon: const Icon(Icons.keyboard),
            onPressed: _handling ? null : _manualEntry,
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraError(
              error: error,
              onManual: _manualEntry,
              onPhoto: _scanFromPhoto,
            ),
          ),
          // Framing guide.
          Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white70, width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          if (_handling)
            Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: const CircularProgressIndicator(),
            ),
          Positioned(
            bottom: 32,
            left: 24,
            right: 24,
            child: Column(
              children: [
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade900.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  )
                else
                  const Text(
                    'Point at the QR code on the desktop app\nSettings → Sharing',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, backgroundColor: Colors.black54),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  final MobileScannerException error;
  final VoidCallback onManual;
  final VoidCallback onPhoto;
  const _CameraError({required this.error, required this.onManual, required this.onPhoto});

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography, color: Colors.white54, size: 48),
          const SizedBox(height: 16),
          Text(
            denied
                ? 'Camera permission is needed to scan the QR code. Grant it in Settings, or use a saved photo / manual entry.'
                : "The camera isn't available here. Scan a saved photo of the QR code, or enter the pairing code manually.",
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onPhoto,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Scan from photo'),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onManual,
            icon: const Icon(Icons.keyboard),
            label: const Text('Enter code manually'),
          ),
        ],
      ),
    );
  }
}
