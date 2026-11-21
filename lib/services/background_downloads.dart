import 'package:flutter/services.dart';

/// 下载后台保活通道：前台服务 + 常驻进度通知。
///
/// 所有调用都吞掉异常——后台能力不可用时不能影响实际下载。
class BackgroundDownloads {
  static const MethodChannel _channel = MethodChannel('pocket_chat/downloads');

  static const int _minIntervalMs = 400;
  static int _lastInvokeMs = 0;
  static int? _lastProgress;
  static String? _lastText;

  static Future<void> ensurePermission() => _invoke('ensurePermission');

  static Future<void> start({
    required String title,
    required String text,
    required int progress,
  }) {
    _resetThrottle();
    return _invoke('start', {
      'title': title,
      'text': text,
      'progress': progress,
    });
  }

  static Future<void> update({required int progress, required String text}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (progress == _lastProgress && text == _lastText) return Future.value();
    if (now - _lastInvokeMs < _minIntervalMs) return Future.value();
    _lastInvokeMs = now;
    _lastProgress = progress;
    _lastText = text;
    return _invoke('update', {'progress': progress, 'text': text});
  }

  static Future<void> stop() {
    _resetThrottle();
    return _invoke('stop');
  }

  static void _resetThrottle() {
    _lastInvokeMs = 0;
    _lastProgress = null;
    _lastText = null;
  }

  static Future<void> _invoke(String method, [Map<String, Object?>? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (_) {
      // 忽略平台通道异常。
    }
  }
}
