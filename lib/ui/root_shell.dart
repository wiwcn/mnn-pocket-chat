import 'package:flutter/material.dart';

import '../state/app_store.dart';
import 'chat/welcome_view.dart';

/// 根导航只承载对话列表，其余页面通过 Navigator.push 打开。
class RootShell extends StatelessWidget {
  const RootShell({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return WelcomeView(store: store);
  }
}
