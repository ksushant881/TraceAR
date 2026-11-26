import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tracear/core/constants.dart';
import 'package:tracear/models/trace_session.dart';

class SessionStore {
  SessionStore({Future<Directory> Function()? docsDirProvider})
    : _docsDirProvider = docsDirProvider ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _docsDirProvider;

  Future<Directory> _sessionsDir() async {
    final docs = await _docsDirProvider();
    final dir = Directory(p.join(docs.path, AppConstants.sessionsDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _sessionFile(String imageId) async {
    final dir = await _sessionsDir();
    return File(p.join(dir.path, '$imageId.json'));
  }

  Future<TraceSession?> load(String imageId) async {
    final file = await _sessionFile(imageId);
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return TraceSession.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  /// Writes are queued so two saves never race on the same temp file.
  Future<void> _writeQueue = Future<void>.value();

  Future<void> save(TraceSession session) {
    final completer = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        await _write(session);
        completer.complete();
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<void> _write(TraceSession session) async {
    final file = await _sessionFile(session.imageId);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(session.toJson()), flush: true);
    // rename() atomically replaces the target on Android/iOS (POSIX).
    // Windows (tests/desktop) can't rename over an existing file.
    if (Platform.isWindows && await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
  }

  Future<void> delete(String imageId) async {
    final file = await _sessionFile(imageId);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
