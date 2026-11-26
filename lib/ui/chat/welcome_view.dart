import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../state/app_store.dart';
import '../models/models_view.dart';
import '../settings/settings_view.dart';
import '../widgets/model_icon.dart';
import 'chat_view.dart';

/// gpt_mobile HomeScreen 的 Flutter 版本：对话列表 + 搜索 + 设置入口。
class WelcomeView extends StatefulWidget {
  const WelcomeView({super.key, required this.store});

  final AppStore store;

  @override
  State<WelcomeView> createState() => _WelcomeViewState();
}

class _WelcomeViewState extends State<WelcomeView>
    with SingleTickerProviderStateMixin {
  final TextEditingController _search = TextEditingController();
  late final AnimationController _entrance;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _search.dispose();
    super.dispose();
  }

  List<ChatSession> _filtered(List<ChatSession> sessions) {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return sessions;
    return sessions
        .where(
          (s) =>
              s.title.toLowerCase().contains(query) ||
              s.modelName.toLowerCase().contains(query),
        )
        .toList();
  }

  void _exitSearch() {
    setState(() {
      _searching = false;
      _search.clear();
    });
  }

  Future<void> _pushChat() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ChatView(store: widget.store)),
    );
  }

  Future<void> _startNewChat() async {
    final store = widget.store;
    final installed = store.catalog.where((m) => store.isInstalled(m.id)).toList();
    if (installed.isEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ModelsView(store: store)),
      );
      return;
    }
    ModelSpec? chosen;
    if (installed.length == 1) {
      // 只有一个已安装模型时无需选择，直接进入（对齐 gpt_mobile 行为）。
      chosen = installed.first;
    } else {
      chosen = await _pickModel(installed);
    }
    if (chosen == null || !mounted) return;
    await store.startChat(chosen);
    await _pushChat();
  }

  /// 新建对话时让用户在已安装模型里手动选择，而不是默认拿第一个。
  Future<ModelSpec?> _pickModel(List<ModelSpec> installed) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return showModalBottomSheet<ModelSpec?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
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
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('选择模型', style: text.titleLarge),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.6,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: installed.length,
                itemBuilder: (context, index) {
                  final model = installed[index];
                  return ListTile(
                    leading: ModelIcon(name: model.name, vendor: model.vendor),
                    title: Text(model.name, maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${model.paramsLabel} · ${model.contextLabel}',
                      maxLines: 1,
                    ),
                    onTap: () => Navigator.of(sheetContext).pop(model),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSession(ChatSession session) async {
    await widget.store.openSession(session);
    await _pushChat();
  }

  Future<void> _confirmDelete(ChatSession session) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除对话？'),
        content: const Text('此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.store.deleteSession(session);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final sessions = _filtered(widget.store.sessions);
        final scheme = Theme.of(context).colorScheme;
        final text = Theme.of(context).textTheme;

        return Scaffold(
          backgroundColor: scheme.surface,
          appBar: AppBar(
            toolbarHeight: 64,
            leading: _searching
                ? IconButton(
                    tooltip: '返回',
                    onPressed: _exitSearch,
                    icon: const Icon(Icons.arrow_back),
                  )
                : IconButton(
                    tooltip: '搜索对话',
                    onPressed: () => setState(() => _searching = true),
                    icon: const Icon(Icons.search),
                  ),
            title: _searching
                ? TextField(
                    controller: _search,
                    autofocus: true,
                    style: text.titleMedium?.copyWith(color: scheme.onSurface),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '搜索对话',
                      hintStyle: text.titleMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  )
                : const Text('对话'),
            actions: [
              if (!_searching)
                IconButton(
                  tooltip: '设置',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SettingsView(store: widget.store),
                    ),
                  ),
                  icon: const Icon(Icons.settings_outlined),
                ),
              if (_searching && _search.text.isNotEmpty)
                IconButton(
                  tooltip: '清除',
                  onPressed: _search.clear,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          floatingActionButton: sessions.isEmpty
              ? null
              : FloatingActionButton.extended(
                  onPressed: _startNewChat,
                  icon: const Icon(Icons.add),
                  label: const Text('新对话'),
                ),
          body: sessions.isEmpty
              ? _EmptyChats(onStart: _startNewChat, searching: _searching)
              : ListView(
                  // AppBar 已有「对话」标题，列表不再重复大字标题；
                  // 顶部留白补偿原 _ChatsTitle 的间距。
                  padding: const EdgeInsets.only(top: 20, bottom: 96),
                  children: [
                    for (var i = 0; i < sessions.length; i++)
                      _SessionItem(
                        session: sessions[i],
                        vendor: widget.store
                                .specFor(sessions[i].modelId)
                                ?.vendor ??
                            '',
                        animation: _entrance,
                        index: i,
                        onTap: () => _openSession(sessions[i]),
                        onLongPress: () => _confirmDelete(sessions[i]),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _SessionItem extends StatelessWidget {
  const _SessionItem({
    required this.session,
    required this.vendor,
    required this.animation,
    required this.index,
    required this.onTap,
    required this.onLongPress,
  });

  final ChatSession session;
  final String vendor;
  final Animation<double> animation;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final start = (index * 40).clamp(0, 340) / 500;
    final end = ((index * 40) + 160).clamp(160, 500) / 500;
    final curve = CurvedAnimation(
      parent: animation,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - curve.value)),
          child: child,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Material(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            onLongPress: onLongPress,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    ModelIcon(name: session.modelName, vendor: vendor),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '使用 ${session.modelName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats({required this.onStart, required this.searching});

  final VoidCallback onStart;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                searching ? '没有搜索结果' : '还没有对话',
                textAlign: TextAlign.center,
                style: text.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                searching ? '换个关键词试试' : '开始一个新的本地对话',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (!searching) ...[
                const SizedBox(height: 24),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: onStart,
                    child: const Text('开始新对话'),
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
