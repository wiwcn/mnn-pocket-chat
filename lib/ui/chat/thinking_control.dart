import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_store.dart';

/// 对话输入栏的思考开关徽章。
///
/// 参考 kelivo 的 reasoning badge 形态（图标 + 短标签，激活时主题色高亮），
/// 但语义严格对齐 MNN 的原生能力：只有开 / 关，没有档位。
class ThinkingBadge extends StatelessWidget {
  const ThinkingBadge({
    super.key,
    required this.enabled,
    required this.onTap,
  });

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Tooltip(
      message: enabled ? '深度思考：开启' : '深度思考：关闭',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: enabled
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                enabled ? Icons.psychology : Icons.psychology_outlined,
                size: 16,
                color: enabled ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                enabled ? '思考' : '不思考',
                style: text.labelSmall?.copyWith(
                  color: enabled ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 思考开关面板。
///
/// 只有「开 / 关」一个原生开关——与 MNN 官方 iOS App 的
/// `setThinkingModeEnabled` 完全一致：向引擎下发
/// `{"jinja":{"context":{"enable_thinking":bool}}}`，无需重新加载模型。
/// MNN 引擎不存在思考预算 / 强度参数，因此这里不再提供虚假档位。
Future<void> showThinkingSheet(
  BuildContext context, {
  required AppStore store,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _ThinkingSheet(store: store),
  );
}

class _ThinkingSheet extends StatefulWidget {
  const _ThinkingSheet({required this.store});

  final AppStore store;

  @override
  State<_ThinkingSheet> createState() => _ThinkingSheetState();
}

class _ThinkingSheetState extends State<_ThinkingSheet> {
  late bool _enabled = widget.store.settings.enableThinking;

  Future<void> _commit(bool value) async {
    if (value == _enabled) return;
    HapticFeedback.selectionClick();
    setState(() => _enabled = value);
    final settings = widget.store.settings;
    settings.enableThinking = value;
    await widget.store.updateSettings(settings);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Icon(Icons.psychology_outlined,
                      color: scheme.primary, size: 22),
                  const SizedBox(width: 10),
                  Text('深度思考', style: text.titleLarge),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              value: _enabled,
              onChanged: _commit,
              title: Text(_enabled ? '开启' : '关闭'),
              subtitle: Text(
                _enabled
                    ? '模型会先输出推理过程，再给出回答'
                    : '直接回答，不输出推理过程',
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '通过模型原生的 enable_thinking 开关控制，切换即时生效、无需重新加载；'
                '本身不支持思考的模型开启后也不会有推理输出。',
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
