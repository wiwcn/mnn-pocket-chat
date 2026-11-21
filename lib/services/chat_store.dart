import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/models.dart';

class ChatStore {
  Future<Directory> _root() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> modelsDir() async {
    final dir = Directory(p.join((await _root()).path, 'models'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<String> modelDir(String id) async =>
      p.join((await modelsDir()).path, id);

  Future<List<ChatSession>> loadSessions() async {
    try {
      final file = File(p.join((await _root()).path, 'sessions.json'));
      if (!await file.exists()) return [];
      final list = jsonDecode(await file.readAsString()) as List;
      return list
          .map((e) => ChatSession.fromJson((e as Map).cast<String, dynamic>()))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSessions(List<ChatSession> sessions) async {
    final file = File(p.join((await _root()).path, 'sessions.json'));
    final trimmed = sessions.take(80).toList();
    await file.writeAsString(jsonEncode(trimmed.map((s) => s.toJson()).toList()));
  }

  Future<Map<String, dynamic>> loadPreferences() async {
    try {
      final file = File(p.join((await _root()).path, 'ui.json'));
      if (!await file.exists()) return {};
      final raw = jsonDecode(await file.readAsString());
      return (raw as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  Future<void> savePreferences(Map<String, dynamic> prefs) async {
    final file = File(p.join((await _root()).path, 'ui.json'));
    await file.writeAsString(jsonEncode(prefs));
  }

  Future<EngineSettings> loadSettings() async {
    try {
      final file = File(p.join((await _root()).path, 'settings.json'));
      if (!await file.exists()) return EngineSettings();
      return EngineSettings.fromJson(
        (jsonDecode(await file.readAsString()) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return EngineSettings();
    }
  }

  Future<void> saveSettings(EngineSettings settings) async {
    final file = File(p.join((await _root()).path, 'settings.json'));
    await file.writeAsString(jsonEncode(settings.toJson()));
  }

  Future<Set<String>> scanInstalled(Set<String> knownIds) async {
    final result = <String>{};
    final dir = await modelsDir();
    await for (final entity in dir.list()) {
      if (entity is! Directory) continue;
      final config = File(p.join(entity.path, 'config.json'));
      if (!await config.exists()) continue;
      final id = p.basename(entity.path);
      if (knownIds.isEmpty || knownIds.contains(id) || await _hasWeights(entity)) {
        result.add(id);
      }
    }
    return result;
  }

  Future<bool> _hasWeights(Directory dir) async {
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.weight')) return true;
    }
    return false;
  }

  Future<int> directorySize(String dirPath) async {
    var total = 0;
    final dir = Directory(dirPath);
    if (!await dir.exists()) return 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }
}
