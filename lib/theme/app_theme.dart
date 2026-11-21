import 'package:flutter/material.dart';

/// gpt_mobile (Compose) 配色的直接移植，不使用 fromSeed。
class AppTheme {
  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF1A6B51),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFA6F2D2),
    onPrimaryContainer: Color(0xFF002116),
    secondary: Color(0xFF4C6359),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFCEE9DB),
    onSecondaryContainer: Color(0xFF092017),
    tertiary: Color(0xFF3F6375),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFC2E8FD),
    onTertiaryContainer: Color(0xFF001F2A),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFF5FBF5),
    onSurface: Color(0xFF171D1A),
    onSurfaceVariant: Color(0xFF404944),
    outline: Color(0xFF707974),
    outlineVariant: Color(0xFFBFC9C2),
    surfaceDim: Color(0xFFD6DBD6),
    surfaceBright: Color(0xFFF5FBF5),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFEFF5F0),
    surfaceContainer: Color(0xFFE9EFEA),
    surfaceContainerHigh: Color(0xFFE4EAE4),
    surfaceContainerHighest: Color(0xFFDEE4DF),
    inverseSurface: Color(0xFF2C322E),
    onInverseSurface: Color(0xFFECF2ED),
    inversePrimary: Color(0xFF8AD6B6),
    scrim: Color(0xFF000000),
    shadow: Color(0xFF000000),
    surfaceTint: Color(0xFF1A6B51),
  );

  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF8AD6B6),
    onPrimary: Color(0xFF003828),
    primaryContainer: Color(0xFF00513C),
    onPrimaryContainer: Color(0xFFA6F2D2),
    secondary: Color(0xFFB3CCBF),
    onSecondary: Color(0xFF1E352C),
    secondaryContainer: Color(0xFF354B41),
    onSecondaryContainer: Color(0xFFCEE9DB),
    tertiary: Color(0xFFA6CCE0),
    onTertiary: Color(0xFF0A3545),
    tertiaryContainer: Color(0xFF264B5C),
    onTertiaryContainer: Color(0xFFC2E8FD),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF0F1512),
    onSurface: Color(0xFFDEE4DF),
    onSurfaceVariant: Color(0xFFBFC9C2),
    outline: Color(0xFF89938D),
    outlineVariant: Color(0xFF404944),
    surfaceDim: Color(0xFF0F1512),
    surfaceBright: Color(0xFF343B37),
    surfaceContainerLowest: Color(0xFF0A0F0D),
    surfaceContainerLow: Color(0xFF171D1A),
    surfaceContainer: Color(0xFF1B211E),
    surfaceContainerHigh: Color(0xFF252B28),
    surfaceContainerHighest: Color(0xFF303633),
    inverseSurface: Color(0xFFDEE4DF),
    onInverseSurface: Color(0xFF2C322E),
    inversePrimary: Color(0xFF1A6B51),
    scrim: Color(0xFF000000),
    shadow: Color(0xFF000000),
    surfaceTint: Color(0xFF8AD6B6),
  );

  /// 默认主题色，与 gpt_mobile 的绿色完全一致。
  static const int defaultSeed = 0xFF1A6B51;

  static ColorScheme schemeFor({
    required Brightness brightness,
    required int seed,
    bool oled = false,
    ColorScheme? dynamic,
  }) {
    final ColorScheme scheme;
    if (dynamic != null) {
      scheme = dynamic;
    } else if (seed == defaultSeed) {
      scheme =
          brightness == Brightness.light ? lightScheme : darkScheme;
    } else {
      scheme = ColorScheme.fromSeed(
        seedColor: Color(seed),
        brightness: brightness,
        dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
      );
    }
    if (!oled || brightness != Brightness.dark) return scheme;
    return scheme.copyWith(
      surface: const Color(0xFF000000),
      surfaceDim: const Color(0xFF000000),
      surfaceContainerLowest: const Color(0xFF000000),
      surfaceContainerLow: const Color(0xFF0A0A0A),
      surfaceContainer: const Color(0xFF121212),
      surfaceContainerHigh: const Color(0xFF1A1A1A),
      surfaceContainerHighest: const Color(0xFF222222),
    );
  }

  static ThemeData build(ColorScheme scheme) {
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    return base.copyWith(
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _FadeThroughPageTransitionsBuilder(),
        },
      ),
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

/// fade-through：淡入 + 轻微上移，220ms，仅用于页面切换。
class _FadeThroughPageTransitionsBuilder extends PageTransitionsBuilder {
  const _FadeThroughPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
