import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_store.dart';
import '../widgets/common.dart';

enum _Filter { all, installed, recommended, thinking }

class ModelsView extends StatefulWidget {
  const ModelsView({super.key, required this.store});

  final AppStore store;

  @override
  State<ModelsView> createState() => _ModelsViewState();
}

class _ModelsViewState extends State<ModelsView> {
  final TextEditingController _search = TextEditingController();
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ModelSpec> get _models {
    final query = _search.text.trim().toLowerCase();
    return widget.store.catalog.where((model) {
      if (_filter == _Filter.installed &&
          !widget.store.isInstalled(model.id)) {
        return false;
      }
      if (_filter == _Filter.recommended && !model.recommended) return false;
      if (_filter == _Filter.thinking && !model.tags.contains('思考')) {
        return false;
      }
      if (query.isEmpty) return true;
      return model.name.toLowerCase().contains(query) ||
          model.vendor.toLowerCase().contains(query) ||
          model.description.toLowerCase().contains(query) ||
          model.tags.any((t) => t.toLowerCase().contains(query));
    }).toList();
  }

  String get _listTitle {
    if (_search.text.trim().isNotEmpty) return '搜索结果';
    switch (_filter) {
      case _Filter.all:
        return '全部模型';
      case _Filter.installed:
        return '已安装';
      case _Filter.recommended:
        return '推荐';
      case _Filter.thinking:
        return '思考模型';
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final models = _models;
    ModelSpec? pocket;
    for (final model in store.catalog) {
      if (model.recommended) {
        pocket = model;
        break;
      }
    }
    final showFeature =
        _filter == _Filter.all && _search.text.isEmpty && pocket != null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        kPagePadding,
        14,
        kPagePadding,
        120,
      ),
      children: [
        PageTitle(
          title: '模型库',
          subtitle:
              '1B 以下 · 端侧优先 · ${store.installed.length} 个已安装',
          trailing: IconButton.filledTonal(
            tooltip: '刷新',
            iconSize: 20,
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _search,
          decoration: InputDecoration(
            hintText: '搜索模型、厂商或标签',
            filled: true,
            fillColor: scheme.surfaceContainerLowest,
            prefixIcon:
                Icon(Icons.search_rounded, size: 20, color: scheme.onSurfaceVariant),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 44, minHeight: 44),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    iconSize: 18,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _search.clear,
                  ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(100),
              borderSide: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(100),
              borderSide: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(100),
              borderSide: BorderSide(color: scheme.primary, width: 1.4),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _filterChip('全部', _Filter.all, models.length),
            _filterChip('已安装', _Filter.installed, null),
            _filterChip('推荐', _Filter.recommended, null),
            _filterChip('思考', _Filter.thinking, null),
          ],
        ),
        const SizedBox(height: 20),
        if (showFeature) ...[
          _PocketBanner(
            model: pocket,
            store: store,
            onDownload: () => _download(context, pocket!),
            onChat: () => store.startChat(pocket!),
          ),
          const SizedBox(height: 24),
        ],
        SectionLabel(
          title: _listTitle,
          trailing: Text(
            '${models.length}',
            style: text.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (models.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: EmptyState(
              icon: Icons.filter_alt_off_rounded,
              title: '没有匹配的模型',
              message: '换个关键词，或切换到「全部」筛选。',
              action: FilledButton.tonal(
                onPressed: () {
                  _search.clear();
                  setState(() => _filter = _Filter.all);
                },
                child: const Text('重置筛选'),
              ),
            ),
          )
        else
          GroupCard(
            child: Column(
              children: [
                for (var i = 0; i < models.length; i++) ...[
                  if (i > 0) const GroupDivider(indent: 68, endIndent: 0),
                  _ModelRow(
                    model: models[i],
                    store: store,
                    onTap: () => _showDetail(context, models[i]),
                    onDownload: () => _download(context, models[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _filterChip(String label, _Filter filter, int? count) {
    final selected = _filter == filter;
    return FilterChip(
      label: Text(count == null ? label : '$label $count'),
      selected: selected,
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: (_) {
        HapticFeedback.selectionClick();
        setState(() => _filter = filter);
      },
    );
  }

  Future<void> _download(BuildContext context, ModelSpec model) async {
    final error = await widget.store.downloadModel(model);
    if (!context.mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  void _showDetail(BuildContext context, ModelSpec model) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ModelDetailSheet(store: widget.store, model: model),
    );
  }
}

class _PocketBanner extends StatelessWidget {
  const _PocketBanner({
    required this.model,
    required this.store,
    required this.onDownload,
    required this.onChat,
  });

  final ModelSpec model;
  final AppStore store;
  final VoidCallback onDownload;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final installed = store.isInstalled(model.id);
    final progress = store.downloads[model.id];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              scheme.primaryContainer.withValues(alpha: 0.55),
              scheme.surfaceContainerLowest,
            ),
            Color.alphaBlend(
              scheme.primaryContainer.withValues(alpha: 0.10),
              scheme.surfaceContainerLowest,
            ),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '精选',
                  style: text.labelSmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '端侧首选',
                style: text.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Icon(Icons.auto_awesome_rounded,
                  size: 20, color: scheme.primary),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            model.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            model.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SoftPill(
                icon: Icons.speed_rounded,
                label: '${model.paramsLabel} 参数',
                background: scheme.surfaceContainerLowest.withValues(alpha: 0.8),
              ),
              SoftPill(
                icon: Icons.sd_storage_rounded,
                label: formatBytes(model.sizeBytes),
                background: scheme.surfaceContainerLowest.withValues(alpha: 0.8),
              ),
              SoftPill(
                icon: Icons.notes_rounded,
                label: '${model.contextLength ~/ 1024}K 上下文',
                background: scheme.surfaceContainerLowest.withValues(alpha: 0.8),
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress.fraction,
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${(progress.fraction * 100).toStringAsFixed(1)}% · '
              '${formatBytes(progress.received)} / ${formatBytes(progress.total)}',
              style: text.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontSize: 11.5,
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: installed
                  ? onChat
                  : progress != null
                      ? () => store.cancelDownload(model.id)
                      : onDownload,
              icon: Icon(
                installed
                    ? Icons.bolt_rounded
                    : progress != null
                        ? Icons.close_rounded
                        : Icons.download_rounded,
                size: 19,
              ),
              label: Text(
                installed
                    ? '开始对话'
                    : progress != null
                        ? '取消下载'
                        : '下载 · ${formatBytes(model.sizeBytes)}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.model,
    required this.store,
    required this.onTap,
    required this.onDownload,
  });

  final ModelSpec model;
  final AppStore store;
  final VoidCallback onTap;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final installed = store.isInstalled(model.id);
    final progress = store.downloads[model.id];

    Widget? trailing;
    if (installed) {
      trailing = Tooltip(
        message: '已安装',
        child: Icon(Icons.check_circle_rounded,
            size: 24, color: scheme.primary),
      );
    } else if (progress != null) {
      trailing = SizedBox(
        width: 30,
        height: 30,
        child: CircularProgressIndicator(
          value: progress.fraction,
          strokeWidth: 3,
          backgroundColor: scheme.surfaceContainerHigh,
        ),
      );
    } else {
      trailing = SizedBox(
        width: 38,
        height: 38,
        child: IconButton.filledTonal(
          padding: EdgeInsets.zero,
          iconSize: 18,
          tooltip: '下载',
          onPressed: onDownload,
          icon: const Icon(Icons.download_rounded),
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Column(
          children: [
            Row(
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
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              model.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (model.recommended) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.verified_rounded,
                                size: 14, color: scheme.primary),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${model.vendor} · ${model.quant}',
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
                const SizedBox(width: 8),
                trailing,
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress.fraction,
                        minHeight: 5,
                        backgroundColor: scheme.surfaceContainerHigh,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${(progress.fraction * 100).toStringAsFixed(0)}% · '
                            '${formatBytes(progress.received)} / ${formatBytes(progress.total)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            minimumSize: const Size(0, 30),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () => store.cancelDownload(model.id),
                          child: const Text('取消'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModelDetailSheet extends StatelessWidget {
  const _ModelDetailSheet({required this.store, required this.model});

  final AppStore store;
  final ModelSpec model;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final installed = store.isInstalled(model.id);
        final progress = store.downloads[model.id];
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const RoundIcon(
                    icon: Icons.memory_rounded,
                    size: 54,
                    iconSize: 26,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(model.name, style: text.headlineSmall),
                        const SizedBox(height: 2),
                        Text(
                          '${model.vendor} · ${model.quant}',
                          style: text.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                model.description,
                style: text.bodyMedium?.copyWith(height: 1.55),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _MetricTile(
                      label: '参数',
                      value: model.paramsLabel,
                      icon: Icons.tune_rounded,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricTile(
                      label: '体积',
                      value: formatBytes(model.sizeBytes),
                      icon: Icons.sd_storage_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _MetricTile(
                      label: '上下文',
                      value: '${model.contextLength ~/ 1024}K',
                      icon: Icons.notes_rounded,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricTile(
                      label: '采样',
                      value:
                          'T ${model.temperature} · P ${model.topP} · K ${model.topK}',
                      icon: Icons.tune_rounded,
                    ),
                  ),
                ],
              ),
              if (progress != null) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress.fraction,
                    minHeight: 6,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${formatBytes(progress.received)} / ${formatBytes(progress.total)}'
                  '${progress.file == null ? '' : ' · ${progress.file}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: installed
                        ? FilledButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              store.startChat(model);
                            },
                            icon: const Icon(Icons.bolt_rounded, size: 19),
                            label: const Text('开始对话'),
                          )
                        : FilledButton.icon(
                            onPressed: progress != null
                                ? () => store.cancelDownload(model.id)
                                : () => store.downloadModel(model),
                            icon: Icon(
                              progress != null
                                  ? Icons.close_rounded
                                  : Icons.download_rounded,
                              size: 19,
                            ),
                            label: Text(
                              progress != null ? '取消下载' : '下载模型',
                            ),
                          ),
                  ),
                  if (installed) ...[
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: '删除模型',
                      onPressed: () => _confirmDelete(context),
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 22),
              Text('模型来源',
                  style:
                      text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              GroupCard(
                padding: const EdgeInsets.all(14),
                radius: 18,
                child: SelectableText(
                  'ModelScope: ${model.modelScopeRepo}\n'
                  'HuggingFace: ${model.hfRepo}',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 17, color: scheme.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '运行时：MNN 3.6.2 · arm64-v8a。'
                        'Pocket 0.3B 使用 tie_embeddings 共享词嵌入，'
                        '需要同一版本族的 MNN 运行时，否则会出现 Load module failed。',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
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
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) await store.deleteModel(model);
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: scheme.onSurfaceVariant),
              const SizedBox(width: 5),
              Text(
                label,
                style: text.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
