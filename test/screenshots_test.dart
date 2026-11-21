import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnn_pocket_chat/core/models.dart';
import 'package:mnn_pocket_chat/state/app_store.dart';
import 'package:mnn_pocket_chat/theme/app_theme.dart';
import 'package:mnn_pocket_chat/ui/chat/chat_view.dart';
import 'package:mnn_pocket_chat/ui/models/models_view.dart';
import 'package:mnn_pocket_chat/ui/root_shell.dart';
import 'package:mnn_pocket_chat/ui/settings/settings_view.dart';
import 'package:mnn_pocket_chat/ui/widgets/model_icon.dart';

const _fontDir = '/opt/flutter/flutter/bin/cache/artifacts/material_fonts';
const _cjkFont = '/usr/share/fonts/truetype/wqy/wqy-microhei.ttc';
const _monoFont = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf';

final bool _canRender = File(_cjkFont).existsSync() &&
    File(_monoFont).existsSync() &&
    File('$_fontDir/MaterialIcons-Regular.otf').existsSync();

Future<void> _loadFont(String family, String path) async {
  final bytes = File(path).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

List<ModelSpec> _catalog() {
  final raw = jsonDecode(File('assets/models.json').readAsStringSync()) as List;
  return raw
      .map((e) => ModelSpec.fromJson((e as Map).cast<String, dynamic>()))
      .toList();
}

const _stats = GenerationStats(
  prefillTps: 120,
  decodeTps: 18.4,
  promptTokens: 64,
  outputTokens: 96,
  elapsedMs: 5200,
);

AppStore _baseStore() {
  final store = AppStore();
  store.catalog = _catalog();
  store.installed.add('MNN-Pocket-0.3B-MNN');
  store.lastStats = _stats;
  store.booting = false;
  return store;
}

AppStore _homeStore() {
  final store = _baseStore();
  final now = DateTime.now();
  store.sessions = [
    ChatSession(
      id: 's3',
      title: '端侧模型的隐私优势',
      modelId: 'MNN-Pocket-0.3B-MNN',
      modelName: 'MNN Pocket 0.3B',
      messages: [ChatMessage(role: ChatRole.user, content: '你好')],
      updatedAt: now.subtract(const Duration(minutes: 4)),
    ),
    ChatSession(
      id: 's2',
      title: '写一个快速排序',
      modelId: 'Qwen3-0.6B-MNN',
      modelName: 'Qwen3 0.6B',
      messages: [ChatMessage(role: ChatRole.user, content: '快排')],
      updatedAt: now.subtract(const Duration(hours: 5)),
    ),
    ChatSession(
      id: 's1',
      title: '介绍一下你自己',
      modelId: 'MiniCPM4-0.5B-MNN',
      modelName: 'MiniCPM4 0.5B',
      messages: [ChatMessage(role: ChatRole.user, content: '你好')],
      updatedAt: now.subtract(const Duration(days: 2)),
    ),
  ];
  return store;
}

AppStore _chatStore() {
  final store = _baseStore();
  final spec = store.specFor('MNN-Pocket-0.3B-MNN')!;
  final session = ChatSession(
    id: 'chat',
    title: '端侧模型的隐私优势',
    modelId: spec.id,
    modelName: spec.name,
    messages: [
      ChatMessage(
        role: ChatRole.user,
        content: '介绍一下你自己，并说明端侧运行的隐私优势。',
      ),
      ChatMessage(
        role: ChatRole.assistant,
        content: '我是 **MNN Pocket 0.3B**，一个为手机端设计的 0.3B 模型。\n\n'
            '1. **数据不出设备**：对话只在本机内存中处理。\n'
            '2. **离线可用**：没有网络也能随时响应。\n'
            '3. **低延迟**：省去上传与排队。',
        stats: _stats,
      ),
      ChatMessage(role: ChatRole.user, content: '帮我写一个 Python 快速排序。'),
      ChatMessage(
        role: ChatRole.assistant,
        content: '可以，下面是一个原地快排实现：\n\n'
            '```python\n'
            'def quick_sort(a, lo=0, hi=None):\n'
            '    if hi is None:\n'
            '        hi = len(a) - 1\n'
            '    if lo >= hi:\n'
            '        return a\n'
            '    pivot, i = a[(lo + hi) // 2], lo\n'
            '    for j in range(lo, hi + 1):\n'
            '        if a[j] < pivot:\n'
            '            a[i], a[j] = a[j], a[i]\n'
            '            i += 1\n'
            '    a[i], a[hi] = a[hi], a[i]\n'
            '    quick_sort(a, lo, i - 1)\n'
            '    quick_sort(a, i + 1, hi)\n'
            '    return a\n'
            '```\n\n'
            '平均时间复杂度 O(n log n)，最坏 O(n²)。',
        stats: _stats,
      ),
    ],
    updatedAt: DateTime.now(),
  );
  store.sessions = [session];
  store.activeSession = session;
  store.activeModel = spec;
  store.modelReady = true;
  return store;
}

AppStore _modelsStore() {
  final store = _baseStore();
  store.installed.add('MiniCPM4-0.5B-MNN');
  store.downloads['Qwen3-0.6B-MNN'] = const DownloadProgress(
    received: 164_000_000,
    total: 454_473_462,
    file: 'llm.mnn.weight',
    bytesPerSecond: 8_600_000,
  );
  return store;
}

ThemeData _theme() => AppTheme.build(AppTheme.lightScheme);

Widget _app(AppStore store, Widget home, {ThemeData? theme}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ?? _theme(),
      home: home,
    );

void main() {
  setUpAll(() async {
    if (!_canRender) return;
    // 用同一字体族名覆盖默认 Roboto，确保按钮与列表项也能渲染中文。
    await _loadFont('Roboto', _cjkFont);
    await _loadFont('MaterialIcons', '$_fontDir/MaterialIcons-Regular.otf');
    await _loadFont('monospace', _monoFont);
  });

  Future<void> prepare(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  Future<void> shot(
    WidgetTester tester,
    AppStore store,
    Widget home,
    String name, {
    ThemeData? theme,
  }) async {
    await prepare(tester);
    // 关掉测试环境对阴影的硬边替代，截图更接近真机。
    debugDisableShadows = false;
    try {
      await tester.pumpWidget(_app(store, home, theme: theme));
      await tester.runAsync(() async {
        final context = tester.element(find.byType(MaterialApp));
        for (final asset in ModelBrand.assets) {
          await precacheImage(
            AssetImage(asset, bundle: DefaultAssetBundle.of(context)),
            context,
          );
        }
      });
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../screenshots/$name.png'),
      );
    } finally {
      debugDisableShadows = true;
    }
  }

  final skip = !_canRender;

  testWidgets('home', (tester) async {
    final store = _homeStore();
    await shot(tester, store, RootShell(store: store), 'brand_home');
  }, skip: skip);

  testWidgets('chat', (tester) async {
    final store = _chatStore();
    await shot(tester, store, ChatView(store: store), 'brand_chat');
  }, skip: skip);

  testWidgets('settings', (tester) async {
    final store = _baseStore();
    await shot(
      tester,
      store,
      SettingsView(store: store),
      'brand_settings',
    );
  }, skip: skip);

  testWidgets('models', (tester) async {
    final store = _modelsStore();
    await shot(tester, store, ModelsView(store: store), 'brand_models');
  }, skip: skip);

  testWidgets('oled', (tester) async {
    final store = _baseStore();
    store.oled = true;
    await shot(
      tester,
      store,
      SettingsView(store: store),
      'brand_oled',
      theme: AppTheme.build(
        AppTheme.schemeFor(
          brightness: Brightness.dark,
          seed: AppTheme.defaultSeed,
          oled: true,
        ),
      ),
    );
  }, skip: skip);
}
