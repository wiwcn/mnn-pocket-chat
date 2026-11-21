import 'dart:io';

import 'package:flutter/services.dart';

/// Opens external links / shares files through the host Android activity.
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

  /// 通过系统分享面板把一个应用私有文件发送出去（如调试日志）。
  static Future<bool> shareFile(String path, {String? mimeType}) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      return await _channel.invokeMethod<bool>('shareFile', {
            'path': path,
            'mimeType': mimeType ?? 'text/plain',
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
