import 'package:flutter/material.dart';

import '../state/app_store.dart';
import 'widgets/common.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Icon(
                    Icons.memory_rounded,
                    color: scheme.onPrimary,
                    size: 42,
                  ),
                ),
                const SizedBox(height: 26),
                Text(
                  'MNN Pocket',
                  style: text.displaySmall?.copyWith(fontSize: 32),
                ),
                const SizedBox(height: 8),
                Text(
                  '本地推理 · 离线可用',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 34),
                Text(
                  '正在准备…',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
