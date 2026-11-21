import 'package:flutter/services.dart';

/// Opens external links through the host Android activity.
class SystemLinks {
  static const MethodChannel _channel = MethodChannel('pocket_chat/system');

  static Future<bool> openUrl(String url) async {
    if (!url.startsWith('https://')) return false;
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ?? false;
    } catch (_) {
      return false;
    }
  }
}
