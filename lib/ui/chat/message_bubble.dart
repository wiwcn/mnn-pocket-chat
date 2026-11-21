import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../widgets/common.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.streaming,
    required this.modelName,
  });

  final ChatMessage message;
  final bool streaming;
  final String modelName;

  @override
  Widget build(BuildContext context) {
    if (message.isUser) return _UserBubble(message: message);
    return _AssistantBubble(
      message: message,
      streaming: streaming,
      modelName: modelName,
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(left: 56, bottom: 14),
        child: GestureDetector(
          onLongPress: () => _copy(context, message.content),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(10),
              ),
            ),
            child: SelectableText(
              message.content,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontSize: 14.5,
                    height: 1.5,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({
    required this.message,
    required this.streaming,
    required this.modelName,
  });

  final ChatMessage message;
  final bool streaming;
  final String modelName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final parts = splitThinking(message.content);
    final showThinking = parts.thinking.trim().isNotEmpty;
    final answer = parts.answer;
    final waitingFirstToken = streaming && message.content.isEmpty;

    return Padding(
      padding: const EdgeInsets.only(right: 18, bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: RoundIcon(
              icon: Icons.auto_awesome_rounded,
              size: 30,
              iconSize: 15,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showThinking)
                  _ThinkingBox(
                    thinking: parts.thinking,
                    open: streaming && answer.isEmpty,
                  ),
                if (waitingFirstToken)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: TypingDots(),
                  )
                else if (answer.trim().isNotEmpty)
                  GestureDetector(
                    onLongPress: () => _copy(context, answer),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLowest,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(24),
                          bottomLeft: Radius.circular(24),
                          bottomRight: Radius.circular(24),
                        ),
                        border: Border.all(
                          color:
                              scheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: StreamingMarkdown(
                        answer: answer,
                        streaming: streaming,
                      ),
                    ),
                  ),
                if (message.stats != null && !streaming)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Row(
                      children: [
                        Icon(Icons.bolt_rounded,
                            size: 13, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 3),
                        Text(
                          '${formatSpeed(message.stats!.decodeTps)} · '
                          '${message.stats!.outputTokens} tokens',
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        SizedBox(
                          width: 30,
                          height: 30,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            tooltip: '复制',
                            iconSize: 15,
                            color: scheme.onSurfaceVariant,
                            onPressed: () => _copy(
                              context,
                              answer.isEmpty ? message.content : answer,
                            ),
                            icon: const Icon(Icons.copy_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingBox extends StatefulWidget {
  const _ThinkingBox({required this.thinking, required this.open});

  final String thinking;
  final bool open;

  @override
  State<_ThinkingBox> createState() => _ThinkingBoxState();
}

class _ThinkingBoxState extends State<_ThinkingBox> {
  late bool _open = widget.open;

  @override
  void didUpdateWidget(covariant _ThinkingBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open && !oldWidget.open) _open = true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 9, 9, 9),
                child: Row(
                  children: [
                    Icon(Icons.psychology_alt_rounded,
                        size: 16, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      '思考过程',
                      style: text.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (widget.open && widget.thinking.trim().isEmpty) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 9,
                        height: 9,
                        child: CircularProgressIndicator(strokeWidth: 1.4),
                      ),
                    ],
                    const Spacer(),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(Icons.expand_more_rounded,
                          size: 19, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(13, 0, 13, 12),
                child: SelectableText(
                  widget.thinking.trim(),
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
              crossFadeState: _open
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
              sizeCurve: Curves.easeOutCubic,
            ),
          ],
        ),
      ),
    );
  }
}

class StreamingMarkdown extends StatelessWidget {
  const StreamingMarkdown({
    super.key,
    required this.answer,
    this.streaming = false,
  });

  final String answer;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final segments = answer.split('```');
    final children = <Widget>[];
    for (var i = 0; i < segments.length; i++) {
      final isCode = i.isOdd;
      var chunk = segments[i];
      if (!isCode) {
        if (chunk.trim().isEmpty) continue;
        children.add(_richChunk(
          chunk.trim(),
          text.bodyMedium?.copyWith(
            fontSize: 14.5,
            height: 1.55,
            color: scheme.onSurface,
          ),
        ));
      } else {
        final lines = chunk.split('\n');
        String? language;
        if (lines.isNotEmpty &&
            lines.first.trim().length < 18 &&
            !lines.first.contains(' ')) {
          language = lines.first.trim();
          chunk = lines.skip(1).join('\n');
        }
        children.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (language != null && language.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    language.toUpperCase(),
                    style: text.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 9.5,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  chunk.trimRight(),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    height: 1.5,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ));
      }
    }
    if (children.isEmpty) {
      children.add(const SizedBox(height: 4));
    }
    if (streaming) {
      children.add(const StreamingCursor());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class StreamingCursor extends StatelessWidget {
  const StreamingCursor({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 16,
      margin: const EdgeInsets.only(top: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class TypingDots extends StatelessWidget {
  const TypingDots({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: 5),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.4 + i * 0.2),
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }
}

/// 轻量渲染 **加粗**，避免小模型输出中的星号直接暴露在气泡里。
Widget _richChunk(String raw, TextStyle? style) {
  final spans = <TextSpan>[];
  var index = 0;
  for (final match in RegExp(r'\*\*(.+?)\*\*', dotAll: true).allMatches(raw)) {
    if (match.start > index) {
      spans.add(TextSpan(text: raw.substring(index, match.start)));
    }
    spans.add(TextSpan(
      text: match.group(1),
      style: const TextStyle(fontWeight: FontWeight.w700),
    ));
    index = match.end;
  }
  if (index < raw.length) {
    spans.add(TextSpan(text: raw.substring(index)));
  }
  if (spans.isEmpty) spans.add(TextSpan(text: raw));
  return SelectableText.rich(TextSpan(style: style, children: spans));
}

({String thinking, String answer}) splitThinking(String raw) {
  const open = '\u003cthink\u003e';
  const close = '\u003c/think\u003e';
  const altOpen = '\u003cthinking\u003e';
  const altClose = '\u003c/thinking\u003e';

  String? thinking;
  String answer = raw;
  for (final pair in [
    (open, close),
    (altOpen, altClose),
  ]) {
    final start = raw.indexOf(pair.$1);
    if (start >= 0) {
      final end = raw.indexOf(pair.$2, start + pair.$1.length);
      if (end >= 0) {
        thinking = raw.substring(start + pair.$1.length, end);
        answer = (raw.substring(0, start) + raw.substring(end + pair.$2.length))
            .trim();
      } else {
        thinking = raw.substring(start + pair.$1.length);
        answer = raw.substring(0, start).trim();
      }
      break;
    }
  }
  return (thinking: thinking ?? '', answer: answer);
}

Future<void> _copy(BuildContext context, String value) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
  );
}
