import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_store.dart';
import '../widgets/common.dart';
import 'session_sheet.dart';

class WelcomeView extends StatelessWidget {
  const WelcomeView({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final installedModels =
        store.catalog.where((m) => store.isInstalled(m.id)).toList();
    final recent = store.sessions.take(3).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        kPagePadding,
        12,
        kPagePadding,
        120,
      ),
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.memory_rounded,
                  color: scheme.onPrimary, size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MNN Pocket',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '本地推理 · 离线可用',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
            const Spacer(),
            IconButton.filledTonal(
              tooltip: '对话历史',
              iconSize: 20,
              onPressed: () => showSessionsSheet(context, store),
              icon: const Icon(Icons.history_rounded),
            ),
          ],
        ),
        if (store.engineError != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded,
                    size: 18, color: scheme.onErrorContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    store.engineError!,
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 28),
        Text(
          '在手机上\n和 0.3B 对话',
          style: text.displaySmall?.copyWith(fontSize: 34, height: 1.16),
        ),
        const SizedBox(height: 12),
        Text(
          '专为 1B 以下端侧模型打造的 MNN 客户端。\n下载、加载、对话，全程离线。',
          style: text.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.55,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: FilledButton.icon(
                onPressed: installedModels.isEmpty
                    ? () => store.setTab(1)
                    : () => showModelPicker(context, store),
                icon: const Icon(Icons.bolt_rounded, size: 20),
                label: const Text('开始对话'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: OutlinedButton(
                onPressed: () => store.setTab(1),
                child: const Text('浏览模型'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        SectionLabel(
          title: '已下载模型',
          trailing: TextButton(
            onPressed: () => store.setTab(1),
            child: const Text('全部'),
          ),
        ),
        if (installedModels.isEmpty)
          GroupCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            onTap: () => store.setTab(1),
            child: Row(
              children: [
                const RoundIcon(icon: Icons.download_for_offline_rounded),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '下载第一个模型',
                        style: text.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '推荐 MNN Pocket 0.3B，仅 166 MB',
                        style: text.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant),
              ],
            ),
          )
        else
          SizedBox(
            height: 164,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: installedModels.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final model = installedModels[index];
                return _QuickModelCard(
                  model: model,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    store.startChat(model);
                  },
                );
              },
            ),
          ),
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 24),
          SectionLabel(
            title: '最近对话',
            trailing: TextButton(
              onPressed: () => showSessionsSheet(context, store),
              child: const Text('历史'),
            ),
          ),
          GroupCard(
            child: Column(
              children: [
                for (var i = 0; i < recent.length; i++) ...[
                  if (i > 0) const GroupDivider(indent: 66, endIndent: 0),
                  _RecentRow(
                    session: recent[i],
                    onTap: () => store.openSession(recent[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _QuickModelCard extends StatelessWidget {
  const _QuickModelCard({required this.model, required this.onTap});

  final ModelSpec model;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SpringScale(
      onTap: onTap,
      child: Container(
        width: 168,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RoundIcon(
              icon: Icons.memory_rounded,
              size: 44,
              iconSize: 22,
            ),
            const Spacer(),
            Text(
              model.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${model.paramsLabel} · ${formatBytes(model.sizeBytes)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    size: 13, color: scheme.primary),
                const SizedBox(width: 4),
                Text(
                  '已安装',
                  style: text.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.session, required this.onTap});

  final ChatSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        child: Row(
          children: [
            const RoundIcon(
              icon: Icons.chat_bubble_outline_rounded,
              size: 40,
              iconSize: 19,
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
                    style: text.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${session.modelName} · ${relativeTime(session.updatedAt)}',
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
            Icon(Icons.chevron_right_rounded,
                size: 20, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
