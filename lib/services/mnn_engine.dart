import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/models.dart';

/// Dart side of the Kotlin/JNI bridge to MNN's libllm.
class MnnEngine {
  static const MethodChannel _methods = MethodChannel('mnn_pocket/engine');
  static const EventChannel _events = EventChannel('mnn_pocket/events');

  final StreamController<EngineEvent> _controller =
      StreamController<EngineEvent>.broadcast();
  StreamSubscription<dynamic>? _subscription;
  final Completer<void> _ready = Completer<void>();

  Stream<EngineEvent> get events => _controller.stream;

  Future<void> initialize() async {
    if (_subscription != null) return;
    _subscription = _events.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          _controller.add(EngineEvent.fromMap(event));
        }
      },
      onError: (Object error) {
        _controller.add(EngineEvent('error', message: error.toString()));
      },
    );
    if (!_ready.isCompleted) _ready.complete();
  }

  Future<bool> load({
    required String configPath,
    required String overridesJson,
  }) async {
    await _ready.future;
    final ok = await _methods.invokeMethod<bool>('load', {
      'configPath': configPath,
      'overrides': overridesJson,
    });
    return ok ?? false;
  }

  Future<void> generate({
    required List<ChatMessage> history,
    required String systemPrompt,
    required int maxTokens,
  }) async {
    final messages = <ChatMessage>[
      if (systemPrompt.trim().isNotEmpty)
        ChatMessage(role: ChatRole.system, content: systemPrompt.trim()),
      ...history,
    ];
    await _methods.invokeMethod<void>('generate', {
      'roles': messages.map((m) => m.role.name).toList(),
      'contents': messages.map((m) => m.content).toList(),
      'maxTokens': maxTokens,
    });
  }

  Future<void> stop() async {
    await _methods.invokeMethod<void>('stop');
  }

  Future<void> reset() async {
    await _methods.invokeMethod<void>('reset');
  }

  Future<void> release() async {
    await _methods.invokeMethod<void>('release');
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _controller.close();
  }

  String encodeOverrides(Map<String, dynamic> overrides) => jsonEncode(overrides);
}
