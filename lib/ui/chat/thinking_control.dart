import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../state/app_store.dart';

/// 思考强度档位徽章：显示在对话输入栏，样式参考 kelivo 的
/// reasoning badge —— 激活时主题色高亮 + 当前档位短标签。
///
/// 只对具备原生推理能力的模型展示（由调用方按 ModelSpec.isReasoning 控制）；
/// 档位 0 = 关闭原生 enable_thinking，档位 1..3 = 开启并注入不同详略的
/// 思考提示词，两者共用同一个 thinkingLevel 状态。
class ThinkingBadge extends StatelessWidget {
  const ThinkingBadge({
    super.key,
    required this.level,
    required this.onTap,
  });

  final int level;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final active = level > 0;
    final label = EngineSettings.thinkingLevelLabels[level.clamp(0, 3)];
    return Tooltip(
      message: '思考强度 · $label',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: active
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? Icons.psychology : Icons.psychology_outlined,
                size: 16,
                color: active ? scheme.primary : scheme.onSurfaceVariant,
              ),
              if (active) ...[
                const SizedBox(width: 4),
                Text(
                  label,
                  style: text.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 思考强度选择面板。样式与交互参考 kelivo / gpt_mobile：
/// 从底部弹出的 sheet + 离散分段滑块 + 当前档位标题 + 副标题说明。
/// 点击档位或拖动滑块即时提交：档位 0 关闭原生思考开关，档位 1..3 在
/// 开启原生思考的同时注入不同详略的提示词，均实时生效、无需重新加载模型。
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
  late int _level = widget.store.settings.thinkingLevel;

  Future<void> _commit(int level) async {
    if (level == _level) return;
    HapticFeedback.selectionClick();
    setState(() => _level = level);
    final settings = widget.store.settings;
    settings.setThinkingLevel(level);
    await widget.store.updateSettings(settings);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final labels = EngineSettings.thinkingLevelLabels;
    final subtitles = EngineSettings.thinkingLevelSubtitles;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Icon(Icons.psychology_outlined, color: scheme.primary, size: 22),
                  const SizedBox(width: 10),
                  Text('思考强度', style: text.titleLarge),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 离散分段滑块：点击档位刻度直接切换，视觉接近 kelivo EffortSlider。
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Column(
                      key: ValueKey(_level),
                      children: [
                        Text(
                          labels[_level],
                          style: text.headlineSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitles[_level],
                          style: text.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 44,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 8,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 13,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 22,
                        ),
                        tickMarkShape: const RoundSliderTickMarkShape(
                          tickMarkRadius: 4,
                        ),
                        activeTrackColor: scheme.primary,
                        inactiveTrackColor:
                            scheme.onSurface.withValues(alpha: 0.12),
                        thumbColor: scheme.primary,
                      ),
                      child: Slider(
                        value: _level.toDouble(),
                        min: 0,
                        max: (EngineSettings.thinkingLevelCount - 1).toDouble(),
                        divisions: EngineSettings.thinkingLevelCount - 1,
                        label: labels[_level],
                        onChanged: (value) => _commit(value.round()),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final label in labels)
                        SizedBox(
                          width: 44,
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: text.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '「关闭」直接关掉原生思考开关；「简洁 / 标准 / 深入」在开启原生思考的同时，'
                '通过系统提示词约束推理详略。均实时生效，无需重新加载模型。',
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
