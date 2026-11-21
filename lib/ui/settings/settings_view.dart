import 'package:flutter/material.dart';

import '../../state/app_store.dart';
import '../widgets/common.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.store});

  final AppStore store;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late double _temperature = widget.store.settings.temperature;
  late double _topP = widget.store.settings.topP;
  late int _topK = widget.store.settings.topK;
  late int _maxTokens = widget.store.settings.maxNewTokens;
  late int _threads = widget.store.settings.threads;
  late String _backend = widget.store.settings.backend;

  void _persist() {
    final settings = widget.store.settings
      ..temperature = _temperature
      ..topP = _topP
      ..topK = _topK
      ..maxNewTokens = _maxTokens
      ..threads = _threads
      ..backend = _backend;
    widget.store.updateSettings(settings);
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        kPagePadding,
        14,
        kPagePadding,
        120,
      ),
      children: [
        PageTitle(
          title: '设置',
          subtitle: '采样、线程与外观。修改生成参数后立即生效。',
        ),
        const SizedBox(height: 26),
        const SectionLabel(title: '生成参数'),
        GroupCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              _SliderTile(
                label: 'Temperature',
                value: _temperature.toStringAsFixed(2),
                description: '越高越有创造性，越低越确定',
                slider: Slider(
                  value: _temperature,
                  min: 0,
                  max: 2,
                  divisions: 40,
                  onChanged: (v) => setState(() => _temperature = v),
                  onChangeEnd: (_) => _persist(),
                ),
              ),
              const GroupDivider(indent: 0, endIndent: 0),
              _SliderTile(
                label: 'Top-P',
                value: _topP.toStringAsFixed(2),
                description: '核采样阈值，0.9 通常是安全值',
                slider: Slider(
                  value: _topP,
                  min: 0.1,
                  max: 1,
                  divisions: 18,
                  onChanged: (v) => setState(() => _topP = v),
                  onChangeEnd: (_) => _persist(),
                ),
              ),
              const GroupDivider(indent: 0, endIndent: 0),
              _SliderTile(
                label: 'Top-K',
                value: '$_topK',
                description: '每步保留的候选 token 数',
                slider: Slider(
                  value: _topK.toDouble(),
                  min: 1,
                  max: 100,
                  divisions: 99,
                  onChanged: (v) => setState(() => _topK = v.round()),
                  onChangeEnd: (_) => _persist(),
                ),
              ),
              const GroupDivider(indent: 0, endIndent: 0),
              _SliderTile(
                label: '最大输出',
                value: '$_maxTokens tokens',
                description: '单次回复的长度上限',
                slider: Slider(
                  value: _maxTokens.toDouble(),
                  min: 64,
                  max: 2048,
                  divisions: 31,
                  onChanged: (v) => setState(() => _maxTokens = v.round()),
                  onChangeEnd: (_) => _persist(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const SectionLabel(title: '系统提示词'),
        GroupCard(
          child: InkWell(
            onTap: () => _editSystemPrompt(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '角色与指令',
                          style: text.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          store.settings.systemPrompt,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.edit_rounded,
                      size: 18, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const SectionLabel(title: '性能'),
        GroupCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '推理后端',
                    style:
                        text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Icon(Icons.memory_rounded,
                      size: 16, color: scheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                _backend == 'cpu'
                    ? 'CPU：兼容性最好，建议 4 线程'
                    : 'OpenCL：部分设备更快，可能不稳定',
                style: text.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'cpu', label: Text('CPU')),
                    ButtonSegment(value: 'opencl', label: Text('OpenCL')),
                  ],
                  selected: {_backend},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) {
                    setState(() => _backend = value.first);
                    _persist();
                  },
                ),
              ),
              const SizedBox(height: 10),
              const GroupDivider(indent: 0, endIndent: 0),
              _SliderTile(
                label: '线程数',
                value: '$_threads',
                description: '小模型 4 线程通常足够',
                slider: Slider(
                  value: _threads.toDouble(),
                  min: 1,
                  max: 8,
                  divisions: 7,
                  onChanged: (v) => setState(() => _threads = v.round()),
                  onChangeEnd: (_) => _persist(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const SectionLabel(title: '外观'),
        GroupCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '主题模式',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_rounded, size: 17),
                      label: Text('系统'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_rounded, size: 17),
                      label: Text('浅色'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_rounded, size: 17),
                      label: Text('深色'),
                    ),
                  ],
                  selected: {store.themeMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) =>
                      store.setThemeMode(value.first),
                ),
              ),
              const SizedBox(height: 10),
              const GroupDivider(indent: 0, endIndent: 0),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: store.dynamicColor,
                onChanged: store.setDynamicColor,
                title: Text(
                  '动态取色',
                  style:
                      text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '从壁纸提取 Material You 配色',
                  style: text.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const SectionLabel(title: '关于'),
        GroupCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Column(
            children: [
              const _AboutRow(label: '版本', value: '0.1.0'),
              const GroupDivider(indent: 0, endIndent: 0),
              const _AboutRow(label: '推理引擎', value: 'MNN 3.6.2'),
              const GroupDivider(indent: 0, endIndent: 0),
              const _AboutRow(label: 'ABI', value: 'arm64-v8a'),
              const GroupDivider(indent: 0, endIndent: 0),
              const _AboutRow(label: '模型范围', value: '≤ 1B · INT4'),
              const GroupDivider(indent: 0, endIndent: 0),
              const _AboutRow(label: '仓库', value: 'taobao-mnn/MNN'),
              const GroupDivider(indent: 0, endIndent: 0),
              _AboutRow(
                label: '开源许可',
                value: '查看',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'MNN Pocket Chat',
                  applicationVersion: '0.1.0',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GroupCard(
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            shape: const Border(),
            collapsedShape: const Border(),
            leading: Icon(
              Icons.help_outline_rounded,
              size: 20,
              color: scheme.primary,
            ),
            title: Text(
              '为什么原版 MNN Chat 跑不了 Pocket 0.3B？',
              style: text.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            children: [
              Text(
                '1. 原版客户端的模型市场 JSON（v22，2026-05）没有收录 2026-11 发布的 MNN-Pocket-0.3B-MNN。\n'
                '2. 原版只扫描 /data/local/tmp/mnn_models，普通用户没有导入入口。\n'
                '3. Pocket 的 llm_config.json 使用 tie_embeddings / alpha_dtype 与 tokenizer.mtok，'
                '需要 MNN 3.6.2 及以上运行时；旧 APK 会报 Load module failed。\n'
                '4. 原始 taobao-mnn/MNN-Pocket-0.3B 仓库是 safetensors，需使用 -MNN 转换版。',
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Text(
            'MNN Pocket Chat · 本地推理，不上传对话',
            style: text.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 11.5,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editSystemPrompt(BuildContext context) async {
    final controller =
        TextEditingController(text: widget.store.settings.systemPrompt);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('系统提示词'),
        content: TextField(
          controller: controller,
          minLines: 4,
          maxLines: 8,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '描述你希望模型扮演的角色',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null) {
      widget.store.settings.systemPrompt = result;
      await widget.store.updateSettings(widget.store.settings);
    }
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.value,
    required this.description,
    required this.slider,
  });

  final String label;
  final String value;
  final String description;
  final Widget slider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  value,
                  style: text.labelSmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            description,
            style: text.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 11.5,
            ),
          ),
          slider,
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Text(
            label,
            style: text.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 12.5,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: text.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
              color: scheme.onSurface,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded,
                size: 17, color: scheme.onSurfaceVariant),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}
