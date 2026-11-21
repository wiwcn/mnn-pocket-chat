import 'package:flutter/material.dart';

import '../../state/app_store.dart';
import '../models/models_view.dart';
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
  late int _threads = widget.store.settings.threads.clamp(1, 8).toInt();
  late String _backend = widget.store.settings.backend;

  void _persist() {
    final settings = widget.store.settings
      ..temperature = _temperature
      ..maxNewTokens = _maxTokens
      ..threads = _threads
      ..backend = _backend;
    widget.store.updateSettings(settings);
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

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
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
                        description: '${store.catalog.length} 个 ≤1B 端侧模型',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ModelsView(store: store),
                          ),
                        ),
                        trailing: const SettingChevron(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SettingsSection(
                    title: '生成',
                    children: [
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
                      const SettingItem(title: '版本', description: '0.2.0'),
                      const SettingItem(
                        title: 'GitHub',
                        description: 'github.com/Taewan-P/gpt_mobile',
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
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.title,
    required this.value,
    required this.slider,
  });

  final String title;
  final String value;
  final Widget slider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SettingItem(title: title, description: value),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: slider,
        ),
      ],
    );
  }
}
