package ai.mnn.mnn_pocket_chat

import ai.mnn.pocket.MnnLlmBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MnnLlmBridge(flutterEngine.dartExecutor.binaryMessenger)
    }
}
