import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  /// [seed] 用于在没有 MaterialApp 祖先时也能着色，避免首帧 Theme.of 抛错。
  const SplashScreen({super.key, this.seed = 0xFF1A6B51});

  final int seed;

  @override
  Widget build(BuildContext context) {
    // 启动首帧本 widget 位于 MaterialApp 之外，Theme.of/Directionality 均缺失；
    // 这里自带一个局部配色方案，杜绝 "Null check operator used on a null value"。
    final scheme = ColorScheme.fromSeed(seedColor: Color(seed));
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: scheme.surface,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.chat_bubble_rounded,
                  color: scheme.onPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
