import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'library_service.dart';

/// Handles inbound shares via receive_sharing_intent.
/// - Android: SEND / SEND_MULTIPLE for audio/* and application/* (m4b/m4a)
/// - iOS: ShareExtension copies files to App Group, plugin surfaces via UserDefaults
/// Maps SharedMediaFile.path -> LibraryService.importFiles
class ShareIntakeService {
  final LibraryService library;
  StreamSubscription<List<SharedMediaFile>>? _sub;
  bool _initialized = false;

  // Supported audio extensions (matches file_picker allow + CFBundleDocumentTypes)
  static const _supportedExts = {
    '.m4b', '.m4a', '.mp3', '.flac', '.ogg', '.wav', '.aac', '.opus',
    '.wma', '.aiff', '.aif', '.mp2', '.mov', '.webm', '.3gp', '.mkv', '.mka',
  };

  ShareIntakeService({required this.library});

  /// Callback when import completes. bookId is null on failure.
  Future<void> Function(String? bookId, List<String> paths)? onImported;
  void Function(String message)? onError;
  void Function(String message)? onInfo;

  Future<void> init({
    Future<void> Function(String? bookId, List<String> paths)? onImported,
    void Function(String message)? onError,
    void Function(String message)? onInfo,
  }) async {
    if (_initialized) return;
    _initialized = true;
    this.onImported = onImported;
    this.onError = onError;
    this.onInfo = onInfo;

    if (kIsWeb) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;

    // Cold start: app launched via share
    await handleInitialMedia();

    // Warm share: app in foreground/background receives SEND
    _sub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> files) async {
        if (files.isEmpty) return;
        debugPrint('ShareIntake: getMediaStream ${files.length} files: ${files.map((f) => f.path).join(", ")}');
        await _handleFiles(files);
        // Clear so same share not re-delivered on next resume
        try { ReceiveSharingIntent.instance.reset(); } catch (_) {}
      },
      onError: (err) {
        debugPrint('ShareIntake stream error: $err');
        onError?.call('Share failed: $err');
      },
    );
  }

  /// Call from AppLifecycleState.resumed or manually to handle any pending share.
  Future<void> handleInitialMedia() async {
    if (kIsWeb) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    try {
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      if (initial.isNotEmpty) {
        debugPrint('ShareIntake: getInitialMedia ${initial.length} files: ${initial.map((f) => f.path).join(", ")}');
        await _handleFiles(initial);
        try { ReceiveSharingIntent.instance.reset(); } catch (_) {}
      }
    } catch (e) {
      debugPrint('ShareIntake getInitialMedia failed: $e');
    }
  }

  Future<void> _handleFiles(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;

    // Collect non-empty paths
    final rawPaths = files
        .map((f) => f.path.trim())
        .where((path) => path.isNotEmpty)
        .toList();

    if (rawPaths.isEmpty) {
      debugPrint('ShareIntake: no paths in share');
      onError?.call('No files in share');
      return;
    }

    // Validate files exist (iOS may provide temp copies that are accessible)
    final existingPaths = <String>[];
    for (final path in rawPaths) {
      // On iOS/Android content URIs may not be File-accessible directly, but plugin already copies to app-accessible path
      // Keep path regardless if we can stat it; let importFiles handle existence check
      // But filter by extension first
      final ext = p.extension(path).toLowerCase();
      if (ext.isEmpty || _supportedExts.contains(ext)) {
        existingPaths.add(path);
      } else {
        debugPrint('ShareIntake: skipping unsupported extension $ext for $path');
      }
    }

    // If filtering removed all, fallback to raw (handles m4b served as application/octet-stream without ext in some share providers)
    final pathsToImport = existingPaths.isNotEmpty ? existingPaths : rawPaths;
    pathsToImport.sort();

    debugPrint('ShareIntake: importing ${pathsToImport.length} files via LibraryService.importFiles');
    onInfo?.call('Importing ${pathsToImport.length} file(s)...');

    try {
      final bookId = await library.importFiles(pathsToImport);
      if (bookId != null) {
        debugPrint('ShareIntake: imported book $bookId');
        await onImported?.call(bookId, pathsToImport);
      } else {
        debugPrint('ShareIntake: importFiles returned null');
        onError?.call('Import failed: could not create book');
        await onImported?.call(null, pathsToImport);
      }
    } catch (e, st) {
      debugPrint('ShareIntake: import failed $e\n$st');
      onError?.call('Import failed: $e');
      await onImported?.call(null, pathsToImport);
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _initialized = false;
  }
}
