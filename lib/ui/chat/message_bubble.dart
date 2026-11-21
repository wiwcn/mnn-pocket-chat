import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.streaming,
  });

  final ChatMessage message;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    if (message.isUser) return _UserBubble(message: message);
    return _AssistantMessage(message: message, streaming: streaming);
  }
}

Future<void> _showCopySheet(BuildContext context, String value) async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: const Text('复制'),
            onTap: () async {
              Navigator.pop(sheetContext);
              await Clipboard.setData(ClipboardData(text: value));
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.8),
              child: GestureDetector(
                onLongPress: () => _showCopySheet(context, message.content),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: Text(
                    message.content,
                    style: text.bodyLarge?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AssistantMessage extends StatelessWidget {
  const _AssistantMessage({required this.message, required this.streaming});

  final ChatMessage message;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final parts = splitThinking(message.content);
    final thinking = parts.thinking.trim();
    final answer = parts.answer;
    final waitingFirstToken = streaming && message.content.trim().isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (thinking.isNotEmpty)
            _ThinkingSection(thinking: thinking, open: streaming && answer.isEmpty),
          Container(
            width: double.infinity,
            color: scheme.surface,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (waitingFirstToken)
                  Text(
                    '●',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                else
                  StreamingMarkdown(answer: answer, streaming: streaming),
              ],
            ),
          ),
          if (!streaming)
            SizedBox(
              width: 40,
              height: 40,
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: '复制',
                iconSize: 20,
                color: scheme.onSurfaceVariant,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: answer));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_outlined),
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
            borderRadius: BorderRadius.circular(32),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '详情',
                    style: text.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
              child: SelectableText(
                widget.thinking,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
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
          text.bodyLarge?.copyWith(color: scheme.onSurface),
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
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
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
    if (streaming) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          '●',
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
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
