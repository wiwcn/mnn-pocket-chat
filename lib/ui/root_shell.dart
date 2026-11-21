import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_store.dart';
import 'chat/chat_view.dart';
import 'chat/welcome_view.dart';
import 'models/models_view.dart';
import 'settings/settings_view.dart';
import 'widgets/common.dart';

class RootShell extends StatelessWidget {
  const RootShell({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
        final scheme = Theme.of(context).colorScheme;
        final chatActive = store.activeSession != null;
        return Scaffold(
          extendBody: false,
          backgroundColor: scheme.surface,
          body: AppBackground(
            child: SafeArea(
              bottom: false,
              child: IndexedStack(
                index: store.tabIndex,
                children: [
                  chatActive
                      ? ChatView(store: store)
                      : WelcomeView(store: store),
                  ModelsView(store: store),
                  SettingsView(store: store),
                ],
              ),
            ),
          ),
          bottomNavigationBar: keyboard
              ? null
              : SafeArea(
                  top: false,
                  minimum: const EdgeInsets.only(bottom: 6),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.6),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: scheme.shadow.withValues(alpha: 0.06),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(32),
                        child: NavigationBar(
                          selectedIndex: store.tabIndex,
                          onDestinationSelected: (index) {
                            HapticFeedback.selectionClick();
                            store.setTab(index);
                          },
                          destinations: const [
                            NavigationDestination(
                              icon: Icon(Icons.chat_bubble_outline_rounded),
                              selectedIcon: Icon(Icons.chat_bubble_rounded),
                              label: '对话',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.grid_view_rounded),
                              selectedIcon: Icon(Icons.dashboard_rounded),
                              label: '模型',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.tune_rounded),
                              selectedIcon: Icon(Icons.tune_rounded),
                              label: '设置',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
