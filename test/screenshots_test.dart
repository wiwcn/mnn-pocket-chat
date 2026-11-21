import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnn_pocket_chat/core/models.dart';
import 'package:mnn_pocket_chat/state/app_store.dart';
import 'package:mnn_pocket_chat/theme/app_theme.dart';
import 'package:mnn_pocket_chat/ui/root_shell.dart';

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

AppStore _store({
  int tab = 0,
  bool withChat = false,
  bool withHistory = false,
  bool withDownload = false,
}) {
  final store = AppStore();
  store.catalog = _catalog();
  store.installed.add('MNN-Pocket-0.3B-MNN');
  store.booting = false;
  store.tabIndex = tab;

  if (withDownload) {
    store.downloads['Qwen3-0.6B-MNN'] = const DownloadProgress(
      received: 164_000_000,
      total: 454_473_462,
      file: 'llm.mnn.weight',
    );
  }

  if (withHistory) {
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
        modelId: 'MNN-Pocket-0.3B-MNN',
        modelName: 'MNN Pocket 0.3B',
        messages: [ChatMessage(role: ChatRole.user, content: '快排')],
        updatedAt: now.subtract(const Duration(hours: 5)),
      ),
      ChatSession(
        id: 's1',
        title: '介绍一下你自己',
        modelId: 'MNN-Pocket-0.3B-MNN',
        modelName: 'MNN Pocket 0.3B',
        messages: [ChatMessage(role: ChatRole.user, content: '你好')],
        updatedAt: now.subtract(const Duration(days: 2)),
      ),
    ];
  }

  if (withChat) {
    final spec = store.specFor('MNN-Pocket-0.3B-MNN')!;
    final session = ChatSession(
      id: 's3',
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
          content:
              '我是 **MNN Pocket 0.3B**，一个专门为手机端设计的 0.3B 参数模型。\n\n'
              '相比云端大模型，我的优势是：\n\n'
              '1. **数据不出设备**：对话内容只在本机内存中处理。\n'
              '2. **离线可用**：没有网络也能随时响应。\n'
              '3. **低延迟**：省去上传与排队，首字通常在一秒内出现。\n\n'
              '当然，我的知识面和推理深度有限，复杂任务仍建议交给更大的模型。',
          stats: const GenerationStats(
            prefillTps: 88.4,
            decodeTps: 41.2,
            promptTokens: 32,
            outputTokens: 128,
            elapsedMs: 3100,
          ),
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
          stats: const GenerationStats(
            prefillTps: 74.1,
            decodeTps: 39.6,
            promptTokens: 168,
            outputTokens: 214,
            elapsedMs: 5400,
          ),
        ),
      ],
      updatedAt: DateTime.now(),
    );
    store.sessions = [session];
    store.activeSession = session;
    store.activeModel = spec;
    store.modelReady = true;
  }

  return store;
}

ThemeData _theme() => AppTheme.build(AppTheme.scheme(Brightness.light, null));

Widget _app(AppStore store) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(),
      home: RootShell(store: store),
    );

void main() {
  setUpAll(() async {
    if (!_canRender) return;
    // 用同一字体族名覆盖默认 Roboto，确保按钮/导航栏等内联样式也能渲染中文。
    await _loadFont('Roboto', _cjkFont);
    await _loadFont('MaterialIcons', '$_fontDir/MaterialIcons-Regular.otf');
    await _loadFont('monospace', _monoFont);
  });

  Future<void> prepare(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  Future<void> shot(WidgetTester tester, AppStore store, String name) async {
    await prepare(tester);
    await tester.pumpWidget(_app(store));
    await tester.pump(const Duration(milliseconds: 80));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../screenshots/$name.png'),
    );
  }

  final skip = !_canRender;

  testWidgets('01 对话首页', (tester) async {
    await shot(tester, _store(withHistory: true), 'm3e_green_01_welcome');
  }, skip: skip);

  testWidgets('02 模型库', (tester) async {
    await shot(tester, _store(tab: 1, withDownload: true), 'm3e_green_02_models');
  }, skip: skip);

  testWidgets('03 聊天', (tester) async {
    await shot(tester, _store(withChat: true), 'm3e_green_03_chat_plain');
  }, skip: skip);

  testWidgets('04 设置', (tester) async {
    await shot(tester, _store(tab: 2), 'm3e_green_04_settings');
  }, skip: skip);

  testWidgets('05 会话历史', (tester) async {
    await prepare(tester);
    final store = _store(withHistory: true);
    await tester.pumpWidget(_app(store));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byTooltip('对话历史'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../screenshots/m3e_green_05_history.png'),
    );
  }, skip: skip);
}
