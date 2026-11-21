import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 日志级别。数值越大越严重。
enum LogLevel {
  debug(0),
  info(1),
  warn(2),
  error(3);

  const LogLevel(this.value);
  final int value;

  String get label => switch (this) {
        LogLevel.debug => 'D',
        LogLevel.info => 'I',
        LogLevel.warn => 'W',
        LogLevel.error => 'E',
      };
}

class LogEntry {
  LogEntry(this.time, this.level, this.tag, this.message);

  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;

  String format() {
    final t = time.toLocal();
    final stamp =
        '${t.year.toString().padLeft(4, '0')}-'
        '${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}.'
        '${t.millisecond.toString().padLeft(3, '0')}';
    return '$stamp ${level.label}/$tag: $message';
  }
}

/// 应用内调试日志：内存环形缓冲 + 落盘到应用私有目录的 debug.log。
///
/// 关键操作前用 [checkpoint] 同步落盘，这样即使随后原生层 SIGSEGV/OOM
/// 闪退，磁盘上也会留下“崩溃前最后一步”，便于在没有 logcat 时定位。
class DebugLog {
  DebugLog._();
  static final DebugLog instance = DebugLog._();

  static const int _maxMemory = 600;
  static const int _maxFileBytes = 2 * 1024 * 1024;

  final List<LogEntry> _entries = <LogEntry>[];
  File? _file;
  Future<void>? _initFuture;
  Future<void> _chain = Future.value();

  /// 是否在记录。默认开启；可在设置里关闭以降低开销。
  bool enabled = true;

  Future<void> init() {
    _initFuture ??= _init();
    return _initFuture!;
  }

  Future<void> _init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      _file = File(p.join(dir.path, 'debug.log'));
      if (!await _file!.exists()) {
        await _file!.writeAsString(
          'Pocket Chat debug log\n'
          'device/app logs, newest at bottom\n'
          '${'-' * 60}\n',
        );
      }
      await _maybeRotate();
    } catch (_) {
      _file = null;
    }
  }

  List<LogEntry> get entries => List.unmodifiable(_entries);

  Future<File?> get file async {
    await init();
    return _file;
  }

  String get logPath => _file?.path ?? '(unavailable)';

  Future<String> read() async {
    await init();
    final f = _file;
    if (f == null) return '日志不可用';
    try {
      return await f.readAsString();
    } catch (e) {
      return '读取日志失败：$e';
    }
  }

  /// 写一条内存日志并异步落盘。适用于 token 等高频但可丢的事件。
  void log(LogLevel level, String tag, String message) {
    if (!enabled) return;
    final entry = LogEntry(DateTime.now(), level, tag, message);
    _entries.add(entry);
    if (_entries.length > _maxMemory) {
      _entries.removeRange(0, _entries.length - _maxMemory);
    }
    _enqueue(entry);
  }

  void debug(String tag, String message) => log(LogLevel.debug, tag, message);
  void info(String tag, String message) => log(LogLevel.info, tag, message);
  void warn(String tag, String message) => log(LogLevel.warn, tag, message);
  void error(String tag, String message) => log(LogLevel.error, tag, message);

  /// 关键操作 checkpoint：调用方应 [await]，确保落盘后再进入原生调用。
  Future<void> checkpoint(String tag, String message) async {
    if (!enabled) return;
    final entry = LogEntry(DateTime.now(), LogLevel.info, tag, message);
    _entries.add(entry);
    if (_entries.length > _maxMemory) {
      _entries.removeRange(0, _entries.length - _maxMemory);
    }
    await _enqueue(entry);
  }

  Future<void> _enqueue(LogEntry entry) {
    final task = _chain.then((_) async {
      final f = _file;
      if (f == null) return;
      try {
        await f.writeAsString('${entry.format()}\n',
            mode: FileMode.append, flush: true);
      } catch (_) {
        // 日志写入失败绝不能影响主流程。
      }
    });
    _chain = task.catchError((_) {});
    return task;
  }

  Future<void> _maybeRotate() async {
    final f = _file;
    if (f == null) return;
    try {
      if (await f.length() <= _maxFileBytes) return;
      final lines = (await f.readAsString()).split('\n');
      final kept = lines.length > 3000 ? lines.sublist(lines.length - 3000) : lines;
      await f.writeAsString('${kept.join('\n')}\n');
    } catch (_) {}
  }

  /// 清空日志（保留文件头）。
  Future<void> clear() async {
    _entries.clear();
    await init();
    final f = _file;
    if (f == null) return;
    try {
      await f.writeAsString(
        'Pocket Chat debug log (cleared)\n'
        '${'-' * 60}\n',
      );
    } catch (_) {}
  }
}

/// 全局便捷入口。
final DebugLog debugLog = DebugLog.instance;
