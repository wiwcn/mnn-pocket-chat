import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_store.dart';
import '../chat/chat_view.dart';
import '../widgets/model_icon.dart';
import '../widgets/common.dart';

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

  AppStore get store => widget.store;

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

  List<ModelSpec> _sortedModels() {
    final models = store.catalog.where(_matches).toList();
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final models = _sortedModels();
        final installed = models.where((m) => store.isInstalled(m.id)).toList();
        final available = models.where((m) => !store.isInstalled(m.id)).toList();

        return Scaffold(
          body: CustomScrollView(
            slivers: [
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
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    children: [
                      _FilterBar(
                        filters: _filters(),
                        selected: _filter,
                        onSelect: (value) => setState(() => _filter = value),
                      ),
                      const SizedBox(height: 8),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: models.isEmpty
                            ? _EmptyResult(
                                key: ValueKey('empty-$_filter'),
                                onClear: _filter == _all
                                    ? null
                                    : () => setState(() => _filter = _all),
                              )
                            : Column(
                                key: ValueKey(_filter),
                                children: [
                                  if (installed.isNotEmpty)
                                    SettingsSection(
                                      title: '已安装',
                                      children: [
                                        for (final model in installed)
                                          _ModelItem(
                                            model: model,
                                            installed: true,
                                            progress: null,
                                            onTap: () =>
                                                _startChat(context, model),
                                            onLongPress: () =>
                                                _confirmDelete(context, model),
                                            onDownload: null,
                                          ),
                                      ],
                                    ),
                                  if (installed.isNotEmpty &&
                                      available.isNotEmpty)
                                    const SizedBox(height: 24),
                                  if (available.isNotEmpty)
                                    SettingsSection(
                                      title: '可下载',
                                      children: [
                                        for (final model in available)
                                          _ModelItem(
                                            model: model,
                                            installed: false,
                                            progress: store.downloads[model.id],
                                            onTap:
                                                store.downloads[model.id] == null
                                                    ? () => _download(
                                                          context,
                                                          model,
                                                        )
                                                    : null,
                                            onLongPress: null,
                                            onDownload: () =>
                                                _download(context, model),
                                          ),
                                      ],
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
  const _EmptyResult({super.key, required this.onClear});

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
          Text('没有符合条件的模型', style: text.titleMedium),
          if (onClear != null) ...[
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onClear,
              child: const Text('清除筛选'),
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
                              child: Text(
                                model.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleMedium,
                              ),
                            ),
                            for (final tag in model.tags.take(2)) ...[
                              const SizedBox(width: 6),
                              _TagPill(label: tag),
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
