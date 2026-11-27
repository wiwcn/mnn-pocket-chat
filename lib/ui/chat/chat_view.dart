import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../services/image_attachments.dart';
import '../../state/app_store.dart';
import '../widgets/model_icon.dart';
import 'message_bubble.dart';
import 'thinking_control.dart';

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
  String? _pendingImage;
  /// 删除当前会话时 activeSession 会被置空。pop 退出动画期间本页仍在树中，
  /// 若此刻按 session==null 重建会出现「闪一下白屏」。缓存最后一帧会话，
  /// 过渡期间继续用它渲染，直到页面真正离树。
  ChatSession? _lastSession;

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
    final image = _pendingImage;
    if ((value.isEmpty && image == null) ||
        widget.store.generating ||
        !widget.store.modelReady) {
      return;
    }
    _input.clear();
    setState(() => _pendingImage = null);
    HapticFeedback.lightImpact();
    widget.store.send(value, imagePath: image);
    _atBottom = true;
  }

  Future<void> _pickImage() async {
    final path = await pickAndStoreImage();
    if (!mounted || path == null) return;
    setState(() => _pendingImage = path);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final store = widget.store;
        final session = store.activeSession;
        // 记住最后一个有效会话，供删除时的 pop 过渡帧使用，避免中间白屏。
        if (session != null) _lastSession = session;
        final viewSession = session ?? _lastSession;
        final scheme = Theme.of(context).colorScheme;
        final text = Theme.of(context).textTheme;
        final modelName =
            store.activeModel?.name ?? viewSession?.modelName ?? '';
        final modelVendor = store.activeModel?.vendor ??
            store.specFor(viewSession?.modelId ?? '')?.vendor ??
            '';

        // 只有从没有过任何会话才显示空态；删除过渡帧用缓存会话继续渲染。
        if (viewSession == null) {
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
              viewSession.title,
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
                icon: ModelIcon(name: modelName, vendor: modelVendor, size: 28),
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
                      // 先弹栈再删除：若先 deleteSession，activeSession 被置空并
                      // notifyListeners，本页在 pop 动画期间会用 session==null
                      // 重建出空白 Scaffold，表现为「闪一下白屏再退出」。
                      // 先 pop 让动画无中间态，再进行持久化删除。
                      final navigator = Navigator.of(context);
                      navigator.pop();
                      await store.deleteSession(viewSession);
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
                if (store.loadHint != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                    child: Row(
                      children: [
                        if (store.modelLoading)
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.primary,
                            ),
                          )
                        else
                          Icon(Icons.check_circle_outline,
                              size: 15, color: scheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            store.loadHint!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
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
                    itemCount: viewSession.messages.length,
                    itemBuilder: (context, index) {
                      final message = viewSession.messages[index];
                      return _BubbleEntrance(
                        key: ObjectKey(message),
                        child: MessageBubble(
                          message: message,
                          streaming: store.generating &&
                              index == viewSession.messages.length - 1 &&
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
                    characters: viewSession.messages.isEmpty
                        ? 0
                        : viewSession.messages.last.content.trim().length,
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                  child: _ChatInputBox(
                    store: store,
                    controller: _input,
                    pendingImage: _pendingImage,
                    onPickImage: _pickImage,
                    onClearImage: () => setState(() => _pendingImage = null),
                    onSend: _send,
                    onConfigureThinking: () =>
                        showThinkingSheet(context, store: store),
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
    required this.pendingImage,
    required this.onPickImage,
    required this.onClearImage,
    required this.onSend,
    required this.onConfigureThinking,
  });

  final AppStore store;
  final TextEditingController controller;
  final String? pendingImage;
  final VoidCallback onPickImage;
  final VoidCallback onClearImage;
  final VoidCallback onSend;
  final VoidCallback onConfigureThinking;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final canSend = (controller.text.trim().isNotEmpty ||
            pendingImage != null) &&
        !store.generating &&
        store.modelReady;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pendingImage != null)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 8),
              child: _PendingImagePreview(
                path: pendingImage!,
                onClear: onClearImage,
              ),
            ),
          Material(
            elevation: 2,
            color: scheme.surfaceContainerHigh,
            surfaceTintColor: Colors.transparent,
            shadowColor: scheme.shadow.withValues(alpha: 0.24),
            borderRadius: BorderRadius.circular(28),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 推理强度只对具备原生思考能力的模型有意义；普通模型
                  // 不展示该入口，避免给出点了也没有效果的按钮。
                  if (store.activeModel?.isReasoning == true)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: ThinkingBadge(
                        level: store.settings.thinkingLevel,
                        onTap: onConfigureThinking,
                      ),
                    ),
                  if (store.activeModel?.vision == true)
                    IconButton(
                      tooltip: '添加图片',
                      iconSize: 22,
                      color: scheme.onSurfaceVariant,
                      onPressed: store.canAttachImage ? onPickImage : null,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
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
                          color:
                              scheme.onSurfaceVariant.withValues(alpha: 0.38),
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
        ],
      ),
    );
  }
}

class _PendingImagePreview extends StatelessWidget {
  const _PendingImagePreview({required this.path, required this.onClear});

  final String path;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(path),
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              errorBuilder: (context, _, _) => Container(
                width: 72,
                height: 72,
                color: scheme.surfaceContainerHighest,
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 24,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: Material(
              color: scheme.surfaceContainerHighest,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onClear,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
