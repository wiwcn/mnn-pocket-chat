import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'state/app_store.dart';
import 'theme/app_theme.dart';
import 'ui/root_shell.dart';

class MnnPocketApp extends StatelessWidget {
  const MnnPocketApp({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        store.themeModeNotifier,
        store.dynamicColorNotifier,
        store.themeSeedNotifier,
        store.oledNotifier,
      ]),
      builder: (context, _) {
        Widget buildWith(ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
          final light = AppTheme.schemeFor(
            brightness: Brightness.light,
            seed: store.themeSeed,
            oled: store.oled,
            dynamic: store.dynamicColor ? lightDynamic : null,
          );
          final dark = AppTheme.schemeFor(
            brightness: Brightness.dark,
            seed: store.themeSeed,
            oled: store.oled,
            dynamic: store.dynamicColor ? darkDynamic : null,
          );
          return MaterialApp(
            title: 'Pocket Chat',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(light),
            darkTheme: AppTheme.build(dark),
            themeMode: store.themeMode,
            home: RootShell(store: store),
          );
        }

        if (!store.dynamicColor) return buildWith(null, null);
        return DynamicColorBuilder(builder: buildWith);
      },
    );
  }
}
