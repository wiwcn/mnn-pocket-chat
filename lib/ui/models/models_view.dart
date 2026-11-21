import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_store.dart';
import '../chat/chat_view.dart';
import '../widgets/model_icon.dart';

class ModelsView extends StatefulWidget {
  const ModelsView({super.key, required this.store});

  final AppStore store;

  @override
  State<ModelsView> createState() => _ModelsViewState();
}

class _ModelsViewState extends State<ModelsView> {
  static const String _all = '全部';
  static const String _installedFilter = '已安装';
  static const String _recommended = '推荐';

  String _filter = _all;
  String _query = '';
  final TextEditingController _searchController = TextEditingController();

  AppStore get store => widget.store;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> _filters() {
    final filters = <String>[_all, _installedFilter, _recommended];
    for (final model in store.catalog) {
      for (final tag in model.tags) {
        if (tag == _recommended) continue;
        if (!filters.contains(tag)) filters.add(tag);
      }
    }
    return filters;
  }

  bool _matches(ModelSpec model) {
    switch (_filter) {
      case _all:
        return true;
      case _installedFilter:
        return store.isInstalled(model.id);
      case _recommended:
        return model.recommended || model.tags.contains(_recommended);
      default:
        return model.tags.contains(_filter);
    }
  }

  bool _matchesQuery(ModelSpec model) {
    if (_query.isEmpty) return true;
    final query = _query.toLowerCase();
    return model.name.toLowerCase().contains(query) ||
        model.vendor.toLowerCase().contains(query) ||
        model.tags.any((tag) => tag.toLowerCase().contains(query));
  }

  List<ModelSpec> _sortedModels() {
    final models =
        store.catalog.where((m) => _matches(m) && _matchesQuery(m)).toList();
    models.sort((a, b) {
      final installedA = store.isInstalled(a.id) ? 0 : 1;
      final installedB = store.isInstalled(b.id) ? 0 : 1;
      if (installedA != installedB) return installedA - installedB;
      if (a.recommended != b.recommended) return a.recommended ? -1 : 1;
      return a.paramsB.compareTo(b.paramsB);
    });
    return models;
  }

  Future<void> _startChat(BuildContext context, ModelSpec model) async {
    await store.startChat(model);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ChatView(store: store)),
    );
  }

  Future<void> _download(BuildContext context, ModelSpec model) async {
    const largeModelBytes = 2 * 1024 * 1024 * 1024;
    if (!store.isInstalled(model.id) && model.sizeBytes >= largeModelBytes) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('下载 ${model.name}'),
          content: Text(
            '下载体积约 ${formatBytes(model.sizeBytes)}。'
            '该模型较大，端侧运行需要充足内存，手机上可能较慢或无法加载。是否继续？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }
    final error = await store.downloadModel(model);
    if (!context.mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _confirmDelete(BuildContext context, ModelSpec model) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除模型？'),
        content: Text('将从本机删除 ${model.name} 的所有文件。'),
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
    if (ok == true) await store.deleteModel(model);
  }

  Widget _sectionHeader(BuildContext context, String title) {
    final scheme = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }

  Widget _modelList(
    List<ModelSpec> models, {
    required bool installedSection,
  }) {
    return SliverList.builder(
      itemCount: models.length,
      itemBuilder: (context, index) {
        final model = models[index];
        final progress = installedSection ? null : store.downloads[model.id];
        return _SectionCard(
          first: index == 0,
          last: index == models.length - 1,
          child: _ModelItem(
            model: model,
            installed: installedSection,
            progress: progress,
            onTap: installedSection
                ? () => _startChat(context, model)
                : progress == null
                    ? () => _download(context, model)
                    : null,
            onLongPress: installedSection
                ? () => _confirmDelete(context, model)
                : null,
            onDownload:
                installedSection ? null : () => _download(context, model),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final models = _sortedModels();
        final installed = models.where((m) => store.isInstalled(m.id)).toList();
        final available = models.where((m) => !store.isInstalled(m.id)).toList();
        final hasConditions = _query.isNotEmpty || _filter != _all;

        final slivers = <Widget>[
          SliverAppBar.large(
            pinned: true,
            leading: IconButton(
              tooltip: '返回',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
            ),
            title: const Text('本地模型'),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: _SearchField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                onClear: () => setState(() {
                  _searchController.clear();
                  _query = '';
                }),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FilterBar(
                filters: _filters(),
                selected: _filter,
                onSelect: (value) => setState(() => _filter = value),
              ),
            ),
          ),
        ];

        if (models.isEmpty) {
          slivers.add(
            SliverToBoxAdapter(
              child: _EmptyResult(
                onClear: hasConditions
                    ? () => setState(() {
                          _searchController.clear();
                          _query = '';
                          _filter = _all;
                        })
                    : null,
              ),
            ),
          );
        } else {
          if (installed.isNotEmpty) {
            slivers.add(_sectionHeader(context, '已安装'));
            slivers.add(_modelList(installed, installedSection: true));
          }
          if (installed.isNotEmpty && available.isNotEmpty) {
            slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));
          }
          if (available.isNotEmpty) {
            slivers.add(_sectionHeader(context, '可下载'));
            slivers.add(_modelList(available, installedSection: false));
          }
        }
        slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));

        return Scaffold(
          body: CustomScrollView(slivers: slivers),
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: BorderSide.none,
    );
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: '搜索模型、厂商或标签',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: '清除搜索',
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClear,
              ),
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: border,
        enabledBorder: border,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: scheme.primary),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.first,
    required this.last,
    required this.child,
  });

  final bool first;
  final bool last;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Material(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.vertical(
              top: first ? const Radius.circular(20) : Radius.zero,
              bottom: last ? const Radius.circular(20) : Radius.zero,
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filters,
    required this.selected,
    required this.onSelect,
  });

  final List<String> filters;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          return Center(
            child: FilterChip(
              label: Text(filter),
              selected: filter == selected,
              showCheckmark: false,
              onSelected: (_) => onSelect(filter),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult({required this.onClear});

  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
      child: Column(
        children: [
          Icon(
            Icons.search_off,
            size: 32,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('没有匹配的模型', style: text.titleMedium),
          if (onClear != null) ...[
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onClear,
              child: const Text('清除搜索与筛选'),
            ),
          ],
        ],
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _ModelItem extends StatelessWidget {
  const _ModelItem({
    required this.model,
    required this.installed,
    required this.progress,
    required this.onTap,
    required this.onLongPress,
    required this.onDownload,
  });

  final ModelSpec model;
  final bool installed;
  final DownloadProgress? progress;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    Widget? trailing;
    if (installed) {
      trailing = Icon(Icons.check, size: 22, color: scheme.primary);
    } else if (progress != null) {
      trailing = _DownloadIndicator(progress: progress!);
    } else {
      trailing = IconButton(
        tooltip: '下载',
        iconSize: 22,
        color: scheme.onSurfaceVariant,
        onPressed: onDownload,
        icon: const Icon(Icons.download_outlined),
      );
    }

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            children: [
              Row(
                children: [
                  ModelIcon(name: model.name, vendor: model.vendor),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              flex: 5,
                              child: Text(
                                model.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleMedium,
                              ),
                            ),
                            for (final tag in model.tags.take(2)) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                flex: 2,
                                child: _TagPill(label: tag),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${model.vendor} · ${formatBytes(model.sizeBytes)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  trailing,
                ],
              ),
              if (progress != null) ...[
                const SizedBox(height: 8),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: progress!.fraction),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  builder: (context, value, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: value, minHeight: 4),
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

class _DownloadIndicator extends StatelessWidget {
  const _DownloadIndicator({required this.progress});

  final DownloadProgress progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: progress.fraction),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, value, _) {
        final speed = progress.bytesPerSecond;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(value * 100).round()}%',
                  style: text.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    value: value,
                    strokeWidth: 2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              speed > 0 ? '${formatBytes(speed.round())}/s' : '连接中',
              style: text.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    );
  }
}
