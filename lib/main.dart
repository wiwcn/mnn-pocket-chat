import 'package:flutter/material.dart';

import 'app.dart';
import 'state/app_store.dart';
import 'ui/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
        if (widget.store.booting) return SplashScreen(store: widget.store);
        return MnnPocketApp(store: widget.store);
      },
    );
  }
}
