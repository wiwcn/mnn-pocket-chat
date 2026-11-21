import 'dart:ui';

import 'package:flutter/material.dart';

import 'app.dart';
import 'services/debug_log.dart';
import 'state/app_store.dart';
import 'ui/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 尽早初始化落盘日志，并接管 Flutter / async 异常，确保崩溃前留下线索。
  await debugLog.init();
  debugLog.info('app', 'launched');
  FlutterError.onError = (details) {
    debugLog.error(
      'flutter',
      '${details.exceptionAsString()}\n${details.stack ?? ''}',
    );
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugLog.error('async', '$error\n$stack');
    return true;
  };

  final store = AppStore();
  runApp(AppBootstrap(store: store));
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key, required this.store});

  final AppStore store;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  @override
  void initState() {
    super.initState();
    widget.store.init();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        if (widget.store.booting) return const SplashScreen();
        return MnnPocketApp(store: widget.store);
      },
    );
  }
}
