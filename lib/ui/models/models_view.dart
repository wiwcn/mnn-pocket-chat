import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_store.dart';
import '../chat/chat_view.dart';
import '../widgets/common.dart';

class ModelsView extends StatelessWidget {
  const ModelsView({super.key, required this.store});

  final AppStore store;

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
        final installed =
            store.catalog.where((m) => store.isInstalled(m.id)).toList();
        final available =
            store.catalog.where((m) => !store.isInstalled(m.id)).toList();

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
                      SettingsSection(
                        title: '已安装',
                        children: installed.isEmpty
                            ? [_EmptyRow(label: '还没有已安装的模型')]
                            : [
                                for (final model in installed)
                                  _ModelItem(
                                    model: model,
                                    installed: true,
                                    progress: null,
                                    onTap: () => _startChat(context, model),
                                    onLongPress: () =>
                                        _confirmDelete(context, model),
                                    onDownload: null,
                                  ),
                              ],
                      ),
                      const SizedBox(height: 24),
                      SettingsSection(
                        title: '可下载',
                        children: available.isEmpty
                            ? [_EmptyRow(label: '全部模型都已安装')]
                            : [
                                for (final model in available)
                                  _ModelItem(
                                    model: model,
                                    installed: false,
                                    progress: store.downloads[model.id],
                                    onTap: store.downloads[model.id] == null
                                        ? () => _download(context, model)
                                        : null,
                                    onLongPress: null,
                                    onDownload: () => _download(context, model),
                                  ),
                              ],
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

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
    final pct = progress == null
        ? 0
        : (progress!.fraction * 100).toStringAsFixed(0);

    Widget? trailing;
    if (installed) {
      trailing = Icon(Icons.check, size: 22, color: scheme.primary);
    } else if (progress != null) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$pct%',
            style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              value: progress!.fraction,
              strokeWidth: 2,
            ),
          ),
        ],
      );
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
                  Icon(
                    installed ? Icons.check_circle : Icons.download_outlined,
                    size: 24,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${model.paramsLabel} · ${model.quant} · '
                          '${formatBytes(model.sizeBytes)}',
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress!.fraction,
                    minHeight: 4,
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
