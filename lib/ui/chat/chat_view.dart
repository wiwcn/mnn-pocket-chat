import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../state/app_store.dart';
import 'message_bubble.dart';
import 'session_sheet.dart';

class ChatView extends StatefulWidget {
  const ChatView({super.key, required this.store});

  final AppStore store;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _atBottom = true;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      _atBottom =
          _scroll.position.maxScrollExtent - _scroll.position.pixels < 90;
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final value = _input.text.trim();
    if (value.isEmpty) return;
    _input.clear();
    HapticFeedback.lightImpact();
    widget.store.send(value);
    _atBottom = true;
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final session = store.activeSession;
    if (session == null) {
      return const SizedBox.shrink();
    }
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_atBottom && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });

    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          _ChatHeader(store: store),
          if (store.engineError != null)
            _ErrorBanner(
              message: store.engineError!,
              onRetry: () {
                final spec = store.activeModel ?? store.specFor(session.modelId);
                if (spec != null) store.loadModel(spec);
              },
            ),
          Expanded(
            child: session.messages.isEmpty
                ? const _ChatEmpty()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: session.messages.length,
                    itemBuilder: (context, index) {
                      final message = session.messages[index];
                      return MessageBubble(
                        message: message,
                        modelName: session.modelName,
                        streaming: store.generating &&
                            index == session.messages.length - 1 &&
                            message.role == ChatRole.assistant,
                      );
                    },
                  ),
          ),
          AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.fromLTRB(12, 0, 12, keyboard ? 8 : 12),
            child: _Composer(
              store: store,
              controller: _input,
              onSend: _send,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final session = store.activeSession!;
    final model = store.activeModel ?? store.specFor(session.modelId);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  model?.name ?? session.modelName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          _HeaderIcon(
            tooltip: '新对话',
            icon: Icons.add_comment_outlined,
            onPressed: store.newChat,
          ),
          _HeaderIcon(
            tooltip: '历史',
            icon: Icons.history_rounded,
            onPressed: () => showSessionsSheet(context, store),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            iconSize: 21,
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (value) async {
              switch (value) {
                case 'clear':
                  await store.clearContext();
                  break;
                case 'release':
                  await store.releaseModel();
                  break;
                case 'settings':
                  store.setTab(2);
                  break;
                case 'delete':
                  await store.deleteSession(session);
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'clear', child: Text('清空上下文')),
              PopupMenuItem(value: 'release', child: Text('释放模型内存')),
              PopupMenuItem(value: 'settings', child: Text('生成参数')),
              PopupMenuItem(value: 'delete', child: Text('删除此对话')),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      height: 38,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        iconSize: 21,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded,
              size: 16, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

class _ChatEmpty extends StatelessWidget {
  const _ChatEmpty();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 34,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 10),
          Text(
            '开始新对话',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.store,
    required this.controller,
    required this.onSend,
  });

  final AppStore store;
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canSend = controller.text.trim().isNotEmpty &&
        !store.generating &&
        store.modelReady;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              enabled: !store.modelLoading,
              textInputAction: TextInputAction.newline,
              keyboardType: TextInputType.multiline,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.4,
                  ),
              decoration: InputDecoration(
                hintText: store.modelReady
                    ? '发消息'
                    : store.modelLoading
                        ? '模型加载中…'
                        : '先选择一个模型',
                filled: false,
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 4),
          if (store.generating)
            _CircleAction(
              color: scheme.error,
              icon: Icons.stop_rounded,
              onTap: store.stopGeneration,
            )
          else
            _CircleAction(
              color: canSend
                  ? scheme.primary
                  : scheme.primary.withValues(alpha: 0.35),
              icon: Icons.arrow_upward_rounded,
              iconColor: scheme.onPrimary,
              onTap: canSend ? onSend : null,
            ),
          const SizedBox(width: 2),
        ],
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.color,
    required this.icon,
    this.iconColor,
    this.onTap,
  });

  final Color color;
  final IconData icon;
  final Color? iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: iconColor ?? Colors.white, size: 21),
      ),
    );
  }
}
