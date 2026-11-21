import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../state/app_store.dart';
import '../widgets/brand_logo.dart';
import 'message_bubble.dart';

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
  Timer? _ticker;
  DateTime? _startedAt;

  @override
  void initState() {
    super.initState();
    _input.addListener(_onInputChanged);
    _scroll.addListener(_onScroll);
    widget.store.addListener(_onStoreChanged);
    if (widget.store.generating) _startTicker();
  }

  void _onStoreChanged() {
    if (widget.store.generating) {
      _startTicker();
    } else {
      _stopTicker();
    }
  }

  void _startTicker() {
    if (_ticker != null) return;
    _startedAt = DateTime.now();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    _startedAt = null;
  }

  void _onInputChanged() => setState(() {});

  void _onScroll() {
    if (!_scroll.hasClients) return;
    _atBottom = _scroll.position.maxScrollExtent - _scroll.position.pixels < 90;
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    _stopTicker();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final value = _input.text.trim();
    if (value.isEmpty || widget.store.generating || !widget.store.modelReady) {
      return;
    }
    _input.clear();
    HapticFeedback.lightImpact();
    widget.store.send(value);
    _atBottom = true;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final store = widget.store;
        final session = store.activeSession;
        final scheme = Theme.of(context).colorScheme;
        final text = Theme.of(context).textTheme;
        final modelName = store.activeModel?.name ?? session?.modelName ?? '';
        final modelVendor = store.activeModel?.vendor ??
            store.specFor(session?.modelId ?? '')?.vendor ??
            '';

        if (session == null) {
          return Scaffold(
            backgroundColor: scheme.surface,
            appBar: AppBar(
              toolbarHeight: 64,
              leading: IconButton(
                tooltip: '返回',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back),
              ),
              title: const Text('对话'),
            ),
          );
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_atBottom || !_scroll.hasClients) return;
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });

        return Scaffold(
          backgroundColor: scheme.surface,
          appBar: AppBar(
            toolbarHeight: 64,
            leading: IconButton(
              tooltip: '返回',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
            ),
            title: Text(
              session.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                tooltip: '模型',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(modelName),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                icon: BrandLogo(vendor: modelVendor, size: 28),
              ),
              PopupMenuButton<String>(
                tooltip: '更多',
                icon: const Icon(Icons.more_vert),
                onSelected: (value) async {
                  switch (value) {
                    case 'clear':
                      await store.clearContext();
                      break;
                    case 'release':
                      await store.releaseModel();
                      break;
                    case 'delete':
                      await store.deleteSession(session);
                      if (!context.mounted) return;
                      Navigator.of(context).maybePop();
                      break;
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'clear', child: Text('清空上下文')),
                  PopupMenuItem(value: 'release', child: Text('释放模型')),
                  PopupMenuItem(value: 'delete', child: Text('删除对话')),
                ],
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                if (store.engineError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Text(
                      store.engineError!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: scheme.error),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: session.messages.length,
                    itemBuilder: (context, index) {
                      final message = session.messages[index];
                      return _BubbleEntrance(
                        key: ObjectKey(message),
                        child: MessageBubble(
                          message: message,
                          streaming: store.generating &&
                              index == session.messages.length - 1 &&
                              message.role == ChatRole.assistant,
                        ),
                      );
                    },
                  ),
                ),
                if (store.generating)
                  _GenerationStatus(
                    elapsed: _startedAt == null
                        ? Duration.zero
                        : DateTime.now().difference(_startedAt!),
                    characters: session.messages.isEmpty
                        ? 0
                        : session.messages.last.content.trim().length,
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                  child: _ChatInputBox(
                    store: store,
                    controller: _input,
                    onSend: _send,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BubbleEntrance extends StatelessWidget {
  const _BubbleEntrance({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _GenerationStatus extends StatelessWidget {
  const _GenerationStatus({required this.elapsed, required this.characters});

  final Duration elapsed;
  final int characters;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final seconds = (elapsed.inMilliseconds / 1000).toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
      child: Row(
        children: [
          Text(
            '生成中 · ${seconds}s',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const Spacer(),
          Text(
            '已生成 $characters 字',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ChatInputBox extends StatelessWidget {
  const _ChatInputBox({
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
    final text = Theme.of(context).textTheme;
    final canSend = controller.text.trim().isNotEmpty &&
        !store.generating &&
        store.modelReady;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        elevation: 2,
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shadowColor: scheme.shadow.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: '附件',
                iconSize: 22,
                color: scheme.onSurfaceVariant,
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('暂不支持附件'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                icon: const Icon(Icons.attach_file),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  enabled: !store.modelLoading,
                  keyboardType: TextInputType.multiline,
                  style: text.bodyLarge?.copyWith(color: scheme.onSurface),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '问点什么…',
                    hintStyle: text.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.38),
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              if (store.generating)
                IconButton(
                  tooltip: '停止',
                  iconSize: 22,
                  onPressed: store.stopGeneration,
                  icon: const Icon(Icons.stop),
                )
              else
                IconButton(
                  tooltip: '发送',
                  iconSize: 22,
                  onPressed: canSend ? onSend : null,
                  icon: const Icon(Icons.send),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
