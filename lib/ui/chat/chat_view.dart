import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../state/app_store.dart';
import '../widgets/common.dart';
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

  void _useSuggestion(String value) {
    _input.text = value;
    _send();
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

    return Column(
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
              ? _ChatEmpty(onSuggestion: _useSuggestion)
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(
                    kPagePadding,
                    8,
                    kPagePadding,
                    16,
                  ),
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
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            keyboard ? 10 : 14,
          ),
          child: _Composer(
            store: store,
            controller: _input,
            onSend: _send,
          ),
        ),
      ],
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
    final status = store.generating
        ? (store.stopping ? '停止中…' : '生成中')
        : store.modelLoading
            ? '加载模型中…'
            : store.modelReady
                ? '已就绪'
                : '模型未加载';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
      child: Row(
        children: [
          const RoundIcon(
            icon: Icons.memory_rounded,
            size: 42,
            iconSize: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: store.modelReady
                            ? scheme.primary
                            : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        '${model?.name ?? session.modelName} · $status',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _HeaderIcon(
            tooltip: '新对话',
            icon: Icons.add_comment_rounded,
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
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 38,
      height: 38,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        iconSize: 21,
        color: scheme.onSurfaceVariant,
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
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 8),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded,
              size: 17, color: scheme.onErrorContainer),
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
  const _ChatEmpty({required this.onSuggestion});

  final ValueChanged<String> onSuggestion;

  static const _suggestions = [
    '用三句话介绍你自己',
    '把这句话翻译成英文：端侧推理正在变快',
    '用 Flutter 写一个 Hello World',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        kPagePadding,
        26,
        kPagePadding,
        20,
      ),
      children: [
        Text('聊点什么？', style: text.headlineMedium),
        const SizedBox(height: 8),
        Text(
          '所有推理都在本机完成，不会上传任何内容。',
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 22),
        GroupCard(
          child: Column(
            children: [
              for (var i = 0; i < _suggestions.length; i++) ...[
                if (i > 0) const GroupDivider(indent: 52),
                InkWell(
                  onTap: () => onSuggestion(_suggestions[i]),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer
                                .withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 15,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _suggestions[i],
                            style: text.bodyMedium?.copyWith(height: 1.4),
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            size: 18, color: scheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
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
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
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
                    ? '发消息…'
                    : store.modelLoading
                        ? '模型加载中…'
                        : '先选择一个模型',
                filled: false,
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              ),
            ),
          ),
          const SizedBox(width: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: store.generating
                ? _CircleAction(
                    key: const ValueKey('stop'),
                    color: scheme.error,
                    icon: Icons.stop_rounded,
                    onTap: store.stopGeneration,
                  )
                : _CircleAction(
                    key: const ValueKey('send'),
                    color: canSend
                        ? scheme.primary
                        : scheme.primary.withValues(alpha: 0.4),
                    icon: Icons.arrow_upward_rounded,
                    iconColor: scheme.onPrimary,
                    onTap: canSend ? onSend : null,
                  ),
          ),
        ],
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    super.key,
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
    return SpringScale(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: iconColor ?? Colors.white, size: 22),
      ),
    );
  }
}
