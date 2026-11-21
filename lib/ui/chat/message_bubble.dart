import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';

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
    return _AssistantMessage(message: message, streaming: streaming);
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
      child: GestureDetector(
        onLongPress: () => _copy(context, message.content),
        child: Container(
          margin: const EdgeInsets.only(left: 64, bottom: 20),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: SelectableText(
            message.content,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: scheme.onSecondaryContainer,
                  fontSize: 14.5,
                  height: 1.5,
                ),
          ),
        ),
      ),
    );
  }
}

class _AssistantMessage extends StatelessWidget {
  const _AssistantMessage({
    required this.message,
    required this.streaming,
  });

  final ChatMessage message;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parts = splitThinking(message.content);
    final showThinking = parts.thinking.trim().isNotEmpty;
    final answer = parts.answer;
    final waitingFirstToken = streaming && message.content.isEmpty;

    return Padding(
      padding: const EdgeInsets.only(right: 12, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showThinking)
            _ThinkingSection(
              thinking: parts.thinking,
              open: streaming && answer.isEmpty,
            ),
          if (waitingFirstToken)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: TypingDots(),
            )
          else if (answer.trim().isNotEmpty)
            GestureDetector(
              onLongPress: () => _copy(context, answer),
              child: StreamingMarkdown(answer: answer, streaming: streaming),
            ),
          if (!streaming && answer.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  tooltip: '复制',
                  iconSize: 16,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                  onPressed: () => _copy(context, answer),
                  icon: const Icon(Icons.copy_rounded),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ThinkingSection extends StatefulWidget {
  const _ThinkingSection({required this.thinking, required this.open});

  final String thinking;
  final bool open;

  @override
  State<_ThinkingSection> createState() => _ThinkingSectionState();
}

class _ThinkingSectionState extends State<_ThinkingSection> {
  late bool _open = widget.open;

  @override
  void didUpdateWidget(covariant _ThinkingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open && !oldWidget.open) _open = true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '思考过程',
                    style: text.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    _open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 8),
              child: SelectableText(
                widget.thinking.trim(),
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
        ],
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
            borderRadius: BorderRadius.circular(12),
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
                      fontWeight: FontWeight.w600,
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
      width: 7,
      height: 15,
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
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }
}

/// 轻量渲染 **加粗**，避免小模型输出中的星号直接暴露在文本里。
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
