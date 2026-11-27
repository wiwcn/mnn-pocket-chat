import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../core/thinking.dart';

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

String _statsLabel(GenerationStats stats) {
  final seconds = (stats.elapsedMs / 1000).toStringAsFixed(1);
  return '${stats.decodeTps.toStringAsFixed(1)} tok/s · '
      '${stats.outputTokens} tokens · ${seconds}s';
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.imagePath != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: 220,
                              maxHeight: 220,
                            ),
                            child: Image.file(
                              File(message.imagePath!),
                              fit: BoxFit.cover,
                              errorBuilder: (context, _, _) => Container(
                                width: 160,
                                height: 120,
                                color: scheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 28,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (message.content.isNotEmpty) const SizedBox(height: 8),
                      ],
                      if (message.content.isNotEmpty)
                        Text(
                          message.content,
                          style: text.bodyLarge?.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                    ],
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
    final parts = cachedSplitThinking(message.content);
    final thinking = parts.thinking.trim();
    final answer = parts.answer;
    final waitingFirstToken = streaming && message.content.trim().isEmpty;
    // 还在推理、且尚无正文时不渲染空的消息气泡，避免出现一片空白容器。
    final hasAnswerBlock =
        answer.isNotEmpty || waitingFirstToken || thinking.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (thinking.isNotEmpty)
            _ThinkingSection(
              key: ValueKey('think_${message.createdAt.microsecondsSinceEpoch}'),
              thinking: thinking,
              state: parts.state,
              streaming: streaming,
            ),
          if (hasAnswerBlock)
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
            Row(
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    tooltip: '复制',
                    iconSize: 18,
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
                if (message.stats != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    _statsLabel(message.stats!),
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _ThinkingSection extends StatefulWidget {
  const _ThinkingSection({
    super.key,
    required this.thinking,
    required this.state,
    required this.streaming,
  });

  final String thinking;
  final ThinkingState state;
  final bool streaming;

  @override
  State<_ThinkingSection> createState() => _ThinkingSectionState();
}

class _ThinkingSectionState extends State<_ThinkingSection> {
  /// 默认收起：只要检测到思考内容就自动折叠成一行，用户点开才展开。
  /// 这是 kelivo 的行为，也是本版的核心诉求。用户的展开/收起选择会
  /// 一直保留到这条消息被重建（key 基于 createdAt，滚动不会重置）。
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final count = widget.thinking.length;
    final thinkingNow = widget.streaming &&
        widget.state == ThinkingState.thinking;

    final String label;
    if (_open) {
      label = '收起思考';
    } else if (thinkingNow) {
      label = count > 0 ? '思考中 · $count 字' : '思考中…';
    } else {
      label = count > 0 ? '已深度思考 · $count 字' : '已深度思考';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    thinkingNow
                        ? Icons.psychology_outlined
                        : Icons.lightbulb_outline,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: text.labelLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 20,
                    color: scheme.primary,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Container(
              margin: const EdgeInsets.only(top: 4, left: 4, right: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: 0.18),
                ),
              ),
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
