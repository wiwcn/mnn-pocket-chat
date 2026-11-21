import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';
import '../services/chat_store.dart';
import '../services/mnn_engine.dart';
import '../services/model_downloader.dart';

class AppStore extends ChangeNotifier {
  AppStore();

  final ChatStore _store = ChatStore();
  final ModelDownloader _downloader = ModelDownloader();
  final MnnEngine engine = MnnEngine();
  StreamSubscription<EngineEvent>? _engineSub;

  List<ModelSpec> catalog = const [];
  final Set<String> installed = {};
  final Map<String, DownloadProgress> downloads = {};
  final Set<String> _cancelled = {};
  List<ChatSession> sessions = [];
  ChatSession? activeSession;
  ModelSpec? activeModel;
  EngineSettings settings = EngineSettings();

  bool booting = true;
  bool modelLoading = false;
  bool modelReady = false;
  bool generating = false;
  bool stopping = false;
  String? engineError;
  int tabIndex = 0;
  ThemeMode themeMode = ThemeMode.system;
  bool dynamicColor = false;
  final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.system);
  final ValueNotifier<bool> dynamicColorNotifier = ValueNotifier<bool>(false);

  String? _streamingSessionId;
  SharedPreferences? _prefs;

  ModelSpec? specFor(String id) {
    for (final m in catalog) {
      if (m.id == id) return m;
    }
    return null;
  }

  bool isInstalled(String id) => installed.contains(id);
  bool isDownloading(String id) => downloads.containsKey(id);

  Future<void> init() async {
    if (!booting) return;
    await engine.initialize();
    _engineSub = engine.events.listen(_onEngineEvent);
    _prefs = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == (_prefs?.getString('themeMode') ?? 'system'),
      orElse: () => ThemeMode.system,
    );
    dynamicColor = _prefs?.getBool('dynamicColor') ?? false;
    themeModeNotifier.value = themeMode;
    dynamicColorNotifier.value = dynamicColor;
    settings = await _store.loadSettings();

    try {
      final raw = jsonDecode(await rootBundle.loadString('assets/models.json'));
      catalog = (raw as List)
          .map((e) => ModelSpec.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (e) {
      engineError = '模型目录加载失败：$e';
    }

    sessions = await _store.loadSessions();
    installed.addAll(await _store.scanInstalled(catalog.map((e) => e.id).toSet()));
    booting = false;
    notifyListeners();
  }

  Future<void> setTab(int index) async {
    tabIndex = index;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    themeModeNotifier.value = mode;
    await _prefs?.setString('themeMode', mode.name);
    notifyListeners();
  }

  Future<void> setDynamicColor(bool value) async {
    dynamicColor = value;
    dynamicColorNotifier.value = value;
    await _prefs?.setBool('dynamicColor', value);
    notifyListeners();
  }

  Future<void> updateSettings(EngineSettings next) async {
    settings = next;
    await _store.saveSettings(next);
    notifyListeners();
  }

  Future<String?> downloadModel(ModelSpec spec) async {
    if (downloads.containsKey(spec.id)) return null;
    _cancelled.remove(spec.id);
    try {
      final files = await _downloader.listFiles(spec);
      final dir = await _store.modelDir(spec.id);
      final root = Directory(dir);
      if (await root.exists()) {
        await root.create(recursive: true);
      }
      downloads[spec.id] = const DownloadProgress(received: 0, total: 0);
      notifyListeners();
      await _downloader.download(
        model: spec,
        files: files,
        destDir: dir,
        onProgress: (progress) {
          downloads[spec.id] = progress;
          notifyListeners();
        },
        isCancelled: () => _cancelled.contains(spec.id),
      );
      installed.add(spec.id);
      downloads.remove(spec.id);
      notifyListeners();
      return null;
    } on DownloadCancelled {
      downloads.remove(spec.id);
      notifyListeners();
      return '已取消下载';
    } catch (e) {
      downloads.remove(spec.id);
      notifyListeners();
      return '下载失败：$e';
    }
  }

  void cancelDownload(String id) {
    _cancelled.add(id);
    downloads.remove(id);
    notifyListeners();
  }

  Future<void> deleteModel(ModelSpec spec) async {
    if (activeModel?.id == spec.id) {
      await engine.release();
      activeModel = null;
      modelReady = false;
    }
    final dir = await _store.modelDir(spec.id);
    final directory = Directory(dir);
    if (await directory.exists()) await directory.delete(recursive: true);
    installed.remove(spec.id);
    notifyListeners();
  }

  Future<String> _configPath(ModelSpec spec) async {
    final dir = await _store.modelDir(spec.id);
    return p.join(dir, 'config.json');
  }

  Future<bool> loadModel(ModelSpec spec) async {
    if (!installed.contains(spec.id)) return false;
    if (activeModel?.id == spec.id && modelReady) return true;
    modelLoading = true;
    engineError = null;
    notifyListeners();
    try {
      await engine.release();
      final path = await _configPath(spec);
      final ok = await engine.load(
        configPath: path,
        overridesJson: settings.encodeOverrides(spec),
      );
      if (!ok) {
        activeModel = null;
        modelReady = false;
        engineError = '模型加载失败：请确认文件完整，或尝试降低线程数';
        return false;
      }
      activeModel = spec;
      modelReady = true;
      return true;
    } catch (e) {
      activeModel = null;
      modelReady = false;
      engineError = '模型加载失败：$e';
      return false;
    } finally {
      modelLoading = false;
      notifyListeners();
    }
  }

  Future<void> startChat(ModelSpec spec) async {
    if (generating) return;
    final ok = await loadModel(spec);
    if (!ok) return;
    final session = ChatSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: '新对话',
      modelId: spec.id,
      modelName: spec.name,
      messages: [],
      updatedAt: DateTime.now(),
    );
    sessions.insert(0, session);
    activeSession = session;
    tabIndex = 0;
    notifyListeners();
  }

  Future<void> openSession(ChatSession session) async {
    if (generating) return;
    final spec = specFor(session.modelId);
    if (spec != null && activeModel?.id != session.modelId) {
      await loadModel(spec);
    }
    activeSession = session;
    tabIndex = 0;
    notifyListeners();
  }

  Future<void> newChat() async {
    if (generating) return;
    final spec = activeModel ??
        (sessions.isNotEmpty ? specFor(sessions.first.modelId) : null);
    if (spec == null) return;
    await startChat(spec);
  }

  Future<void> deleteSession(ChatSession session) async {
    sessions.removeWhere((s) => s.id == session.id);
    if (activeSession?.id == session.id) activeSession = null;
    await _store.saveSessions(sessions);
    notifyListeners();
  }

  Future<void> send(String text) async {
    final session = activeSession;
    if (session == null || generating || !modelReady) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    session.messages.add(ChatMessage(role: ChatRole.user, content: trimmed));
    if (session.messages.length == 1) {
      session.title = trimmed.length > 24 ? '${trimmed.substring(0, 24)}…' : trimmed;
    }
    session.messages.add(ChatMessage(role: ChatRole.assistant, content: ''));
    session.updatedAt = DateTime.now();
    _streamingSessionId = session.id;
    generating = true;
    stopping = false;
    engineError = null;
    notifyListeners();

    final history = session.messages
        .where((m) => m != session.messages.last)
        .toList();
    try {
      await engine.generate(
        history: history,
        systemPrompt: settings.systemPrompt,
        maxTokens: settings.maxNewTokens,
      );
    } catch (e) {
      generating = false;
      stopping = false;
      _streamingSessionId = null;
      session.messages.last.content = '生成失败：$e';
      notifyListeners();
    }
  }

  Future<void> clearContext() async {
    if (generating) return;
    await engine.reset();
    activeSession?.messages.clear();
    notifyListeners();
  }

  Future<void> stopGeneration() async {
    if (!generating) return;
    stopping = true;
    notifyListeners();
    await engine.stop();
  }

  void _onEngineEvent(EngineEvent event) {
    final session = activeSession;
    if (session == null) return;
    switch (event.type) {
      case 'token':
        if (_streamingSessionId != session.id) return;
        session.messages.last.content += event.text ?? '';
        notifyListeners();
        break;
      case 'done':
        if (_streamingSessionId != session.id) return;
        generating = false;
        stopping = false;
        _streamingSessionId = null;
        session.messages.last.stats = event.stats;
        session.updatedAt = DateTime.now();
        sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        unawaited(_store.saveSessions(sessions));
        notifyListeners();
        break;
      case 'error':
        if (_streamingSessionId != session.id) return;
        generating = false;
        stopping = false;
        _streamingSessionId = null;
        final message = event.message ?? '未知错误';
        engineError = message;
        if (session.messages.isNotEmpty && session.messages.last.content.isEmpty) {
          session.messages.last.content = '生成失败：$message';
        }
        notifyListeners();
        break;
    }
  }

  Future<void> releaseModel() async {
    await engine.release();
    modelReady = false;
    activeModel = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _engineSub?.cancel();
    engine.dispose();
    _downloader.dispose();
    super.dispose();
  }
}
