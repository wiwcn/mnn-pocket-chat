import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../services/system_links.dart';
import '../../state/app_store.dart';
import '../debug/debug_view.dart';
import '../models/models_view.dart';
import '../widgets/model_icon.dart';
import '../widgets/common.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.store});

  final AppStore store;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late double _temperature =
      widget.store.settings.temperature.clamp(0.0, 2.0).toDouble();
  late int _maxTokens =
      widget.store.settings.maxNewTokens.clamp(64, 2048).toInt();
  late int _contextMessages =
      widget.store.settings.contextMessages.clamp(4, 40).toInt();
  late double _topP = widget.store.settings.topP.clamp(0.1, 1.0).toDouble();
  late int _topK = widget.store.settings.topK.clamp(1, 100).toInt();
  late int _threads = widget.store.settings.threads.clamp(1, 8).toInt();
  late String _backend = widget.store.settings.backend;
  late bool _useMmap = widget.store.settings.useMmap;
  late bool _enableThinking = widget.store.settings.enableThinking;
  late int _thinkingBudget = widget.store.settings.thinkingBudget.clamp(0, 8192);
  late String _systemPrompt = widget.store.settings.systemPrompt;

  Future<void> _open(String url) async {
    await SystemLinks.openUrl(url);
  }

  void _persist() {
    final settings = widget.store.settings
      ..temperature = _temperature
      ..maxNewTokens = _maxTokens
      ..contextMessages = _contextMessages
      ..topP = _topP
      ..topK = _topK
      ..threads = _threads
      ..backend = _backend
      ..enableThinking = _enableThinking
      ..thinkingBudget = _thinkingBudget
      ..systemPrompt = _systemPrompt;
    widget.store.updateSettings(settings);
  }

  ModelSpec? _installedModel(AppStore store) {
    for (final model in store.catalog) {
      if (store.installed.contains(model.id)) return model;
    }
    return null;
  }

  String _modeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
      case ThemeMode.system:
        return '跟随系统';
    }
  }

  String get _backendLabel => _backend == 'cpu' ? 'CPU' : 'OpenCL';

  Future<void> _pickTheme() async {
    final store = widget.store;
    final mode = await showDialog<ThemeMode>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('主题设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in ThemeMode.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_modeLabel(option)),
                trailing: Icon(
                  option == store.themeMode
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 22,
                ),
                onTap: () => Navigator.pop(context, option),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (mode != null) await store.setThemeMode(mode);
  }

  Future<void> _editPerformance() async {
    var backend = _backend;
    var threads = _threads;
    final result = await showDialog<({String backend, int threads})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('性能'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final option in const ['cpu', 'opencl'])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(option == 'cpu' ? 'CPU' : 'OpenCL'),
                  trailing: Icon(
                    backend == option
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 22,
                  ),
                  onTap: () => setDialogState(() => backend = option),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('线程数'),
                  const Spacer(),
                  Text('$threads'),
                ],
              ),
              Slider(
                value: threads.toDouble(),
                min: 1,
                max: 8,
                divisions: 7,
                onChanged: (value) =>
                    setDialogState(() => threads = value.round()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, (backend: backend, threads: threads)),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      _backend = result.backend;
      _threads = result.threads;
    });
    _persist();
  }

  Future<void> _editSystemPrompt() async {
    final controller = TextEditingController(text: _systemPrompt);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('系统提示词'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 8,
            minLines: 4,
            decoration: const InputDecoration(
              hintText: '给模型的角色设定与行为约束',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null) return;
    setState(() => _systemPrompt = result);
    _persist();
  }

  Future<void> _editThinkingBudget() async {
    var budget = _thinkingBudget;
    final result = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('思考强度'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(budget == 0
                  ? '不限制（由模型自行决定思考长度）'
                  : '约 $budget tokens'),
              Slider(
                value: budget.toDouble(),
                min: 0,
                max: 8192,
                divisions: 16,
                onChanged: (value) =>
                    setDialogState(() => budget = value.round()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, budget),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    setState(() => _thinkingBudget = result);
    _persist();
  }

  Future<void> _toggleMmap(bool value) async {
    setState(() => _useMmap = value);
    await widget.store.setUseMmap(value);
  }

  void _openDebug() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DebugView(store: widget.store),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final installedModel = _installedModel(store);
        final stats = store.lastStats;
        final speedText = stats == null
            ? '尚无记录'
            : '${stats.decodeTps.toStringAsFixed(1)} tok/s · '
                '${stats.outputTokens} tokens';
        return Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverAppBar.large(
                pinned: true,
                leading: IconButton(
                  tooltip: '返回',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                ),
                title: const Text('设置'),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    children: [
                      SettingsSection(
                        title: '外观',
                        children: [
                          SettingItem(
                            title: '主题设置',
                            description: _modeLabel(store.themeMode),
                            onTap: _pickTheme,
                            trailing: const SettingChevron(),
                          ),
                          _ThemeColorSetting(
                            selected: store.themeSeed,
                            onSelect: store.setThemeSeed,
                          ),
                          SettingItem(
                            title: '纯黑背景（OLED）',
                            description: '深色模式下使用纯黑，更省电',
                            trailing: Switch(
                              value: store.oled,
                              onChanged: store.setOled,
                            ),
                          ),
                          SettingItem(
                            title: '动态取色',
                            trailing: Switch(
                              value: store.dynamicColor,
                              onChanged: store.setDynamicColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SettingsSection(
                        title: '模型',
                        children: [
                          SettingItem(
                            title: '本地模型',
                            description: '${store.catalog.length} 个可离线运行的模型',
                            leading: ModelIcon(
                              name: installedModel?.name ?? 'Pocket Chat',
                              vendor: installedModel?.vendor ?? 'Alibaba MNN',
                            ),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ModelsView(store: store),
                              ),
                            ),
                            trailing: const SettingChevron(),
                          ),
                          SettingItem(
                            title: '内存映射加载（mmap）',
                            description: _useMmap
                                ? '已开启 · 降低内存占用，推荐'
                                : '已关闭 · 整块加载',
                            trailing: Switch(
                              value: _useMmap,
                              onChanged: _toggleMmap,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SettingsSection(
                        title: '生成',
                        children: [
                          SettingItem(
                            title: '系统提示词',
                            description: _systemPrompt.length > 40
                                ? '${_systemPrompt.substring(0, 40)}…'
                                : _systemPrompt,
                            onTap: _editSystemPrompt,
                            trailing: const SettingChevron(),
                          ),
                          SettingItem(
                            title: '深度思考',
                            description: _enableThinking
                                ? '已开启 · 思考模型输出推理过程'
                                : '已关闭 · 直接给出答案',
                            trailing: Switch(
                              value: _enableThinking,
                              onChanged: (value) {
                                setState(() => _enableThinking = value);
                                _persist();
                              },
                            ),
                          ),
                          if (_enableThinking)
                            SettingItem(
                              title: '思考强度',
                              description: _thinkingBudget == 0
                                  ? '不限制 · 由模型自行决定'
                                  : '约 $_thinkingBudget tokens',
                              onTap: _editThinkingBudget,
                              trailing: const SettingChevron(),
                            ),
                          _SliderSetting(
                            title: '最大输出',
                            value: '$_maxTokens tokens',
                            slider: Slider(
                              value: _maxTokens.toDouble(),
                              min: 64,
                              max: 2048,
                              divisions: 31,
                              onChanged: (value) =>
                                  setState(() => _maxTokens = value.round()),
                              onChangeEnd: (_) => _persist(),
                            ),
                          ),
                          _SliderSetting(
                            title: '温度',
                            value: _temperature.toStringAsFixed(2),
                            slider: Slider(
                              value: _temperature,
                              min: 0,
                              max: 2,
                              divisions: 40,
                              onChanged: (value) =>
                                  setState(() => _temperature = value),
                              onChangeEnd: (_) => _persist(),
                            ),
                          ),
                          _SliderSetting(
                            title: '上下文长度',
                            value: '$_contextMessages 条消息',
                            caption:
                                '保留最近 $_contextMessages 条历史，模型上限 32K',
                            slider: Slider(
                              value: _contextMessages.toDouble(),
                              min: 4,
                              max: 40,
                              divisions: 18,
                              onChanged: (value) => setState(
                                () => _contextMessages = value.round(),
                              ),
                              onChangeEnd: (_) => _persist(),
                            ),
                          ),
                          _SliderSetting(
                            title: 'Top-P',
                            value: _topP.toStringAsFixed(2),
                            slider: Slider(
                              value: _topP,
                              min: 0.1,
                              max: 1.0,
                              divisions: 18,
                              onChanged: (value) =>
                                  setState(() => _topP = value),
                              onChangeEnd: (_) => _persist(),
                            ),
                          ),
                          _SliderSetting(
                            title: 'Top-K',
                            value: '$_topK',
                            slider: Slider(
                              value: _topK.toDouble(),
                              min: 1,
                              max: 100,
                              divisions: 99,
                              onChanged: (value) =>
                                  setState(() => _topK = value.round()),
                              onChangeEnd: (_) => _persist(),
                            ),
                          ),
                          SettingItem(
                            title: '最近速度',
                            description: '$speedText\n每次回答后实测',
                          ),
                          SettingItem(
                            title: '性能',
                            description: '$_backendLabel / $_threads 线程',
                            onTap: _editPerformance,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SettingsSection(
                        title: '关于',
                        children: [
                          const SettingItem(title: '版本', description: '1.4.0'),
                          SettingItem(
                            title: '调试日志',
                            description: '查看并导出运行日志，用于排查闪退',
                            onTap: _openDebug,
                            trailing: const SettingChevron(),
                          ),
                          SettingItem(
                            title: 'GitHub',
                            description: 'github.com/wiwcn/pocket-chat',
                            onTap: () => _open('https://github.com/wiwcn/pocket-chat'),
                          ),
                          SettingItem(
                            title: '界面参考',
                            description: 'Taewan-P/gpt_mobile',
                            onTap: () =>
                                _open('https://github.com/Taewan-P/gpt_mobile'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ThemeColorSetting extends StatelessWidget {
  const _ThemeColorSetting({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  static const List<({String name, int hex})> colors = [
    (name: '绿', hex: 0xFF1A6B51),
    (name: '青', hex: 0xFF00696E),
    (name: '蓝', hex: 0xFF2F5DA8),
    (name: '紫', hex: 0xFF6B4FA1),
    (name: '橙', hex: 0xFFA45A00),
    (name: '粉', hex: 0xFF9C4063),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('主题色', style: text.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final color in colors)
                Tooltip(
                  message: color.name,
                  child: Semantics(
                    label: '主题色 ${color.name}',
                    button: true,
                    selected: selected == color.hex,
                    child: GestureDetector(
                      onTap: () => onSelect(color.hex),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        width: selected == color.hex ? 38 : 36,
                        height: selected == color.hex ? 38 : 36,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected == color.hex
                                ? scheme.onSurface
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          width: selected == color.hex ? 30 : 28,
                          height: selected == color.hex ? 30 : 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(color.hex),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.title,
    required this.value,
    required this.slider,
    this.caption,
  });

  final String title;
  final String value;
  final Widget slider;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SettingItem(title: title, description: value),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: slider,
        ),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                caption!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
      ],
    );
  }
}
