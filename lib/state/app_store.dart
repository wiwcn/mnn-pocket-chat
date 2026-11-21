import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../services/background_downloads.dart';
import '../services/chat_store.dart';
import '../services/debug_log.dart';
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
  /// 模型加载过程的可见提示（"正在加载…" / "已就绪"）。
  String? loadHint;
  Timer? _loadHintTimer;
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

  // 反退化兜底：小模型长生成时可能陷入重复循环，反复吐同一 token（如「H」）。
  // 采样层惩罚之外，这里检测尾部短模式的连续重复，命中即自动停止。
  bool _repetitionStopped = false;

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
    debugLog.info('app', 'init start');
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
      debugLog.info('app',
          'init done: catalog=${catalog.length}, installed=${installed.length}, sessions=${sessions.length}, useMmap=${settings.useMmap}');
    } catch (e) {
      // 任一步失败都不能让 App 永远卡在启动闪屏。
      engineError = '初始化失败：$e';
      debugLog.error('app', 'init failed: $e');
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

  /// 更新 mmap 开关。已加载模型时先释放，下次加载按新设置生效。
  Future<void> setUseMmap(bool value) async {
    if (settings.useMmap == value) return;
    settings.useMmap = value;
    await _store.saveSettings(settings);
    debugLog.info('settings', 'useMmap=$value');
    if (modelReady) {
      await debugLog.checkpoint('model', 'reload after mmap toggle');
      await engine.release();
      modelReady = false;
      activeModel = null;
      loadHint = '加载方式已更新，下次进入对话将重新加载';
    }
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
    debugLog.info('download', 'start: ${spec.id} (${spec.sizeBytes} bytes)');
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
      debugLog.info('download', 'done: ${spec.id}');
      return null;
    } on DownloadCancelled {
      downloads.remove(spec.id);
      _downloadTicks.remove(spec.id);
      _stopDownloadNotificationIfIdle();
      notifyListeners();
      debugLog.info('download', 'cancelled: ${spec.id}');
      return '已取消下载';
    } catch (e) {
      downloads.remove(spec.id);
      _downloadTicks.remove(spec.id);
      _stopDownloadNotificationIfIdle();
      notifyListeners();
      debugLog.error('download', 'failed: ${spec.id}, $e');
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
    loadHint = '正在加载 ${spec.name}…';
    notifyListeners();
    await debugLog.checkpoint('model',
        'load start: id=${spec.id}, params=${spec.paramsLabel}, useMmap=${settings.useMmap}, threads=${settings.threads}, backend=${settings.backend}');
    try {
      await engine.release();
      final path = await _configPath(spec);
      // 用应用私有目录作为 mmap 临时路径，降低大模型推理时的内存峰值。
      // 只有设置里开启 mmap 时才创建并使用该目录。
      String? mmapDir;
      if (settings.useMmap) {
        try {
          final root = await _store.modelsDir();
          mmapDir = p.join(root.path, '.mmap');
          await Directory(mmapDir).create(recursive: true);
        } catch (_) {
          mmapDir = null;
        }
      }

      final overrides =
          settings.encodeOverrides(spec, mmapDir: mmapDir);
      await debugLog.checkpoint('model', 'native load begin: $overrides');
      var ok = await engine.load(
        configPath: path,
        overridesJson: overrides,
      );
      // 部分模型/设备不支持 mmap，回退到整块加载再试一次。
      if (!ok && mmapDir != null && settings.useMmap) {
        await debugLog.checkpoint('model', 'mmap load failed, retry without mmap');
        ok = await engine.load(
          configPath: path,
          overridesJson:
              settings.encodeOverrides(spec, useMmapOverride: false),
        );
      }
      await debugLog.checkpoint('model', 'native load result: $ok');
      if (!ok) {
        activeModel = null;
        modelReady = false;
        engineError = '模型加载失败：请确认文件完整，或尝试降低线程数';
        loadHint = null;
        debugLog.error('model', 'load failed: ${spec.id}');
        return false;
      }
      activeModel = spec;
      modelReady = true;
      loadHint = '${spec.name} 已就绪';
      _loadHintTimer?.cancel();
      _loadHintTimer = Timer(const Duration(seconds: 3), () {
        if (loadHint == '${spec.name} 已就绪') {
          loadHint = null;
          notifyListeners();
        }
      });
      return true;
    } catch (e) {
      activeModel = null;
      modelReady = false;
      engineError = '模型加载失败：$e';
      loadHint = null;
      debugLog.error('model', 'load exception: $e');
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
    _repetitionStopped = false;
    notifyListeners();
    await debugLog.checkpoint('chat',
        'generate begin: session=${session.id}, history=${session.messages.length - 1}, maxTokens=${settings.maxNewTokens}, image=${imagePath != null}');

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
      debugLog.error('chat', 'generate exception: $e');
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
      case 'stage':
        // native 阶段打点：直接落盘， assistance 崩溃时也能看到执行到哪一步。
        debugLog.info('native', event.message ?? '');
        break;
      case 'token':
        if (session == null || session.messages.isEmpty) return;
        if (session.messages.last.content.isEmpty) {
          debugLog.info('chat', 'first token received');
        }
        if (_repetitionStopped) return; // 已因退化停止，忽略后续残留 token
        session.messages.last.content += event.text ?? '';
        // 反退化兜底：检测尾部短模式连续重复，命中则自动停止生成本轮。
        if (_isDegenerateRepeat(session.messages.last.content)) {
          _repetitionStopped = true;
          stopping = true;
          debugLog.error('chat',
              'degenerate repetition detected, auto-stopping generation');
          unawaited(engine.stop());
        }
        notifyListeners();
        break;
      case 'done':
        debugLog.info('chat',
            'generate done: output=${event.stats?.outputTokens ?? 0}, elapsed=${event.stats?.elapsedMs ?? 0}ms');
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
        debugLog.error('engine', 'generate error: $message');
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

  /// 检测文本尾部是否出现退化式重复：某个长度 1~12 的模式连续重复多次。
  /// 典型症状是「H」或「哈哈哈哈」或整句循环。仅检查尾部窗口，避免误判
  /// 正文里合法的少量重复；需连续重复达到阈值才判定，防止正常文本被截断。
  bool _isDegenerateRepeat(String text) {
    // 只在积累到一定长度后检测，且只看尾部 400 字，控制开销。
    if (text.length < 8) return false;
    final window = text.length > 400 ? text.substring(text.length - 400) : text;
    // 单个字符连续重复：如 HHHHHHHH…（用户报告的「一长串 H」）。
    if (_trailingCharRepeat(window) >= 12) return true;
    // 短模式（2~12 字）连续重复 >= 4 次。
    for (var len = 2; len <= 12; len++) {
      if (window.length < len * 4) break;
      final tail = window.substring(window.length - len * 4);
      final block = tail.substring(0, len);
      var allSame = true;
      for (var i = 1; i < 4; i++) {
        if (tail.substring(i * len, (i + 1) * len) != block) {
          allSame = false;
          break;
        }
      }
      if (allSame) return true;
    }
    return false;
  }

  /// 末尾同一字符连续出现的次数。
  int _trailingCharRepeat(String text) {
    if (text.isEmpty) return 0;
    final last = text.codeUnitAt(text.length - 1);
    var count = 0;
    for (var i = text.length - 1; i >= 0; i--) {
      if (text.codeUnitAt(i) != last) break;
      count++;
    }
    return count;
  }

  Future<void> releaseModel() async {
    if (generating) {
      await stopGeneration();
      _finishStreaming();
    }
    await debugLog.checkpoint('model', 'release begin');
    await engine.release();
    modelReady = false;
    activeModel = null;
    debugLog.info('model', 'released');
    notifyListeners();
  }

  @override
  void dispose() {
    _loadHintTimer?.cancel();
    _engineSub?.cancel();
    engine.dispose();
    _downloader.dispose();
    super.dispose();
  }
}
