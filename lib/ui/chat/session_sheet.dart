import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_store.dart';
import '../widgets/common.dart';

Future<void> showSessionsSheet(BuildContext context, AppStore store) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final scheme = Theme.of(context).colorScheme;
          final text = Theme.of(context).textTheme;
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.62,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            builder: (context, controller) {
              return ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(
                  kPagePadding,
                  0,
                  kPagePadding,
                  28,
                ),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '对话历史',
                          style: text.headlineSmall,
                        ),
                      ),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 14),
                          backgroundColor: scheme.primaryContainer,
                          foregroundColor: scheme.onPrimaryContainer,
                          textStyle: text.labelMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          store.newChat();
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('新对话'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (store.sessions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      child: Center(
                        child: Text(
                          '还没有对话',
                          style: text.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  else
                    GroupCard(
                      child: Column(
                        children: [
                          for (var i = 0;
                              i < store.sessions.length;
                              i++) ...[
                            if (i > 0)
                              const GroupDivider(indent: 64, endIndent: 0),
                            _SessionRow(
                              session: store.sessions[i],
                              onTap: () {
                                Navigator.pop(context);
                                store.openSession(store.sessions[i]);
                              },
                              onDelete: () =>
                                  store.deleteSession(store.sessions[i]),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              );
            },
          );
        },
      );
    },
  );
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.session,
    required this.onTap,
    required this.onDelete,
  });

  final ChatSession session;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Row(
          children: [
            const RoundIcon(
              icon: Icons.forum_rounded,
              size: 40,
              iconSize: 19,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
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
            IconButton(
              tooltip: '删除',
              iconSize: 19,
              color: scheme.onSurfaceVariant,
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showModelPicker(BuildContext context, AppStore store) async {
  final models = store.catalog.where((m) => store.isInstalled(m.id)).toList();
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final scheme = Theme.of(context).colorScheme;
          final text = Theme.of(context).textTheme;
          return Padding(
            padding: const EdgeInsets.fromLTRB(kPagePadding, 0, kPagePadding, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('选择一个模型', style: text.headlineSmall),
                const SizedBox(height: 16),
                if (models.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(
                        '还没有已下载的模型，先去模型库下载一个吧',
                        style: text.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  GroupCard(
                    child: Column(
                      children: [
                        for (var i = 0; i < models.length; i++) ...[
                          if (i > 0)
                            const GroupDivider(indent: 64, endIndent: 0),
                          InkWell(
                            onTap: () {
                              Navigator.pop(context);
                              store.startChat(models[i]);
                            },
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  14, 12, 10, 12),
                              child: Row(
                                children: [
                                  const RoundIcon(
                                    icon: Icons.memory_rounded,
                                    size: 40,
                                    iconSize: 19,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          models[i].name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: text.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '${models[i].paramsLabel} · '
                                          '${formatBytes(models[i].sizeBytes)} · '
                                          '${models[i].quant}',
                                          style: text.bodySmall?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right_rounded,
                                      size: 20,
                                      color: scheme.onSurfaceVariant),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      );
    },
  );
}
