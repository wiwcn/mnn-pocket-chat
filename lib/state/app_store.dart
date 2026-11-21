import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../services/background_downloads.dart';
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
  int themeSeed = 0xFF1A6B51;
  bool oled = false;
  GenerationStats? lastStats;
  final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.system);
  final ValueNotifier<bool> dynamicColorNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> themeSeedNotifier =
      ValueNotifier<int>(0xFF1A6B51);
  final ValueNotifier<bool> oledNotifier = ValueNotifier<bool>(false);

  String? _streamingSessionId;
  Map<String, dynamic> _prefs = {};
  final Map<String, DateTime> _downloadTicks = {};

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
    try {
      await engine.initialize();
      _engineSub = engine.events.listen(_onEngineEvent);
      _prefs = await _store.loadPreferences();
      themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == (_prefs['themeMode'] as String? ?? 'system'),
        orElse: () => ThemeMode.system,
      );
      dynamicColor = _prefs['dynamicColor'] as bool? ?? false;
      themeSeed = _prefs['themeSeed'] as int? ?? 0xFF1A6B51;
      oled = _prefs['oledMode'] as bool? ?? false;
      themeModeNotifier.value = themeMode;
      dynamicColorNotifier.value = dynamicColor;
      themeSeedNotifier.value = themeSeed;
      oledNotifier.value = oled;
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
      installed.addAll(
        await _store.scanInstalled(catalog.map((e) => e.id).toSet()),
      );
    } catch (e) {
      // 任一步失败都不能让 App 永远卡在启动闪屏。
      engineError = '初始化失败：$e';
    } finally {
      booting = false;
      notifyListeners();
    }
  }

  Future<void> setTab(int index) async {
    tabIndex = index;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    themeModeNotifier.value = mode;
    _prefs['themeMode'] = mode.name;
    await _store.savePreferences(_prefs);
    notifyListeners();
  }

  Future<void> setDynamicColor(bool value) async {
    dynamicColor = value;
    dynamicColorNotifier.value = value;
    _prefs['dynamicColor'] = value;
    await _store.savePreferences(_prefs);
    notifyListeners();
  }

  Future<void> setThemeSeed(int value) async {
    themeSeed = value;
    themeSeedNotifier.value = value;
    _prefs['themeSeed'] = value;
    await _store.savePreferences(_prefs);
    notifyListeners();
  }

  Future<void> setOled(bool value) async {
    oled = value;
    oledNotifier.value = value;
    _prefs['oledMode'] = value;
    await _store.savePreferences(_prefs);
    notifyListeners();
  }

  Future<void> updateSettings(EngineSettings next) async {
    settings = next;
    await _store.saveSettings(next);
    notifyListeners();
  }

  DownloadProgress _withSpeed(String id, DownloadProgress next) {
    final now = DateTime.now();
    final previous = downloads[id];
    final lastTick = _downloadTicks[id];
    var speed = previous?.bytesPerSecond ?? 0;
    if (previous != null && lastTick != null) {
      final elapsed = now.difference(lastTick).inMilliseconds;
      final delta = next.received - previous.received;
      if (elapsed >= 300 && delta > 0) {
        final instant = delta * 1000 / elapsed;
        speed = speed <= 0 ? instant : speed * 0.65 + instant * 0.35;
        _downloadTicks[id] = now;
      }
    } else {
      _downloadTicks[id] = now;
    }
    return DownloadProgress(
      received: next.received,
      total: next.total,
      file: next.file,
      bytesPerSecond: speed,
    );
  }

  Future<String?> downloadModel(ModelSpec spec) async {
    if (downloads.containsKey(spec.id)) return null;
    _cancelled.remove(spec.id);
    try {
      unawaited(BackgroundDownloads.ensurePermission());
      unawaited(BackgroundDownloads.start(
        title: '正在下载 ${spec.name}',
        text: '准备中…',
        progress: -1,
      ));
      final files = await _downloader.listFiles(spec);
      final dir = await _store.modelDir(spec.id);
      final root = Directory(dir);
      if (await root.exists()) {
        await root.create(recursive: true);
      }
      downloads[spec.id] = const DownloadProgress(received: 0, total: 0);
      _downloadTicks.remove(spec.id);
      notifyListeners();
      await _downloader.download(
        model: spec,
        files: files,
        destDir: dir,
        onProgress: (progress) {
          downloads[spec.id] = _withSpeed(spec.id, progress);
          _updateDownloadNotification();
          notifyListeners();
        },
        isCancelled: () => _cancelled.contains(spec.id),
      );
      installed.add(spec.id);
      downloads.remove(spec.id);
      _downloadTicks.remove(spec.id);
      _stopDownloadNotificationIfIdle();
      notifyListeners();
      return null;
    } on DownloadCancelled {
      downloads.remove(spec.id);
      _downloadTicks.remove(spec.id);
      _stopDownloadNotificationIfIdle();
      notifyListeners();
      return '已取消下载';
    } catch (e) {
      downloads.remove(spec.id);
      _downloadTicks.remove(spec.id);
      _stopDownloadNotificationIfIdle();
      notifyListeners();
      return '下载失败：$e';
    }
  }

  void cancelDownload(String id) {
    _cancelled.add(id);
    downloads.remove(id);
    _downloadTicks.remove(id);
    _stopDownloadNotificationIfIdle();
    notifyListeners();
  }

  /// 将所有进行中下载的已接收/总字节聚合成一条通知进度。
  void _updateDownloadNotification() {
    if (downloads.isEmpty) return;
    var received = 0;
    var total = 0;
    for (final progress in downloads.values) {
      received += progress.received;
      total += progress.total;
    }
    final percent = total <= 0
        ? 0
        : ((received * 100) / total).round().clamp(0, 100).toInt();
    final text = downloads.length == 1
        ? '${specFor(downloads.keys.first)?.name ?? '模型'} · $percent%'
        : '${downloads.length} 个模型 · $percent%';
    unawaited(BackgroundDownloads.update(progress: percent, text: text));
  }

  void _stopDownloadNotificationIfIdle() {
    if (downloads.isEmpty) {
      unawaited(BackgroundDownloads.stop());
    }
  }

  Future<void> deleteModel(ModelSpec spec) async {
    if (activeModel?.id == spec.id) {
      // 删除当前模型前先结束生成，避免模型文件被删除时引擎仍在使用。
      if (generating) {
        await stopGeneration();
        _finishStreaming();
      }
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
    // 删除正在流式输出的会话时，先请求停止，避免引擎回调丢失导致
    // generating 永久为 true、App 卡死在"生成中"。
    if (generating && _streamingSessionId == session.id) {
      await stopGeneration();
      _finishStreaming();
    }
    sessions.removeWhere((s) => s.id == session.id);
    if (activeSession?.id == session.id) activeSession = null;
    await _store.saveSessions(sessions);
    notifyListeners();
  }

  /// 统一收尾流式状态，确保任何路径都不会把 generating 卡在 true。
  void _finishStreaming({GenerationStats? stats}) {
    generating = false;
    stopping = false;
    _streamingSessionId = null;
    if (stats != null) lastStats = stats;
  }

  bool get canAttachImage =>
      modelReady && !generating && activeModel?.vision == true;

  Future<void> send(String text, {String? imagePath}) async {
    final session = activeSession;
    if (session == null || generating || !modelReady) return;
    var trimmed = text.trim();
    if (trimmed.isEmpty && imagePath == null) return;
    if (trimmed.isEmpty) trimmed = '描述这张图片。';

    session.messages.add(ChatMessage(
      role: ChatRole.user,
      content: trimmed,
      imagePath: imagePath,
    ));
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
        .map((m) => ChatMessage(
              role: m.role,
              content: m.engineContent,
              stats: m.stats,
              createdAt: m.createdAt,
            ))
        .toList();
    final limit = settings.contextMessages.clamp(1, 200);
    final recent = history.length > limit
        ? history.sublist(history.length - limit)
        : history;
    try {
      await engine.generate(
        history: recent,
        systemPrompt: settings.systemPrompt,
        maxTokens: settings.maxNewTokens,
      );
    } catch (e) {
      _finishStreaming();
      if (session.messages.isNotEmpty) {
        session.messages.last.content = '生成失败：$e';
      }
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
    final streamId = _streamingSessionId;
    // 事件必须归属到发起生成的会话，而不是"当前打开的会话"——后者在
    // 生成期间可能已被删除/切换，导致 token/done 被吞、generating 卡死。
    if (streamId == null) return;
    ChatSession? session;
    for (final candidate in sessions) {
      if (candidate.id == streamId) {
        session = candidate;
        break;
      }
    }

    switch (event.type) {
      case 'token':
        if (session == null || session.messages.isEmpty) return;
        session.messages.last.content += event.text ?? '';
        notifyListeners();
        break;
      case 'done':
        _finishStreaming(stats: event.stats);
        if (session != null && session.messages.isNotEmpty) {
          session.messages.last.stats = event.stats;
          session.updatedAt = DateTime.now();
          sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          unawaited(_store.saveSessions(sessions));
        }
        notifyListeners();
        break;
      case 'error':
        _finishStreaming();
        final message = event.message ?? '未知错误';
        engineError = message;
        if (session != null &&
            session.messages.isNotEmpty &&
            session.messages.last.content.isEmpty) {
          session.messages.last.content = '生成失败：$message';
        }
        notifyListeners();
        break;
    }
  }

  Future<void> releaseModel() async {
    if (generating) {
      await stopGeneration();
      _finishStreaming();
    }
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
