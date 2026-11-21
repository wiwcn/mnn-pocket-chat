import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../core/models.dart';

class RemoteFile {
  const RemoteFile({required this.path, required this.size, required this.url});

  final String path;
  final int size;
  final String url;
}

class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

class DownloadException implements Exception {
  DownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ModelDownloader {
  ModelDownloader({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, List<RemoteFile>> _cache = {};
  static const String _ua =
      'MnnPocketChat/0.1 (Flutter; on-device MNN client)';

  Future<List<RemoteFile>> listFiles(ModelSpec model) async {
    final cached = _cache[model.id];
    if (cached != null) return cached;

    List<RemoteFile>? files;
    try {
      files = await _listFromModelScope(model);
    } catch (_) {
      files = null;
    }
    if (files == null || files.isEmpty) {
      try {
        files = await _listFromHuggingFace(model);
      } catch (_) {
        files = null;
      }
    }
    if (files == null || files.isEmpty) {
      throw DownloadException('无法获取 ${model.name} 的文件列表，请检查网络后重试');
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    _cache[model.id] = files;
    return files;
  }

  Future<List<RemoteFile>> _listFromModelScope(ModelSpec model) async {
    final uri = Uri.parse(
      'https://modelscope.cn/api/v1/models/${model.modelScopeRepo}/repo/files'
      '?Revision=master',
    );
    final res = await _client
        .get(uri, headers: {'User-Agent': _ua})
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw DownloadException('ModelScope ${res.statusCode}');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
    if (body['Code'] != 200) throw DownloadException('ModelScope error');
    final list = ((body['Data'] as Map)['Files'] as List).cast<Map>();
    final result = <RemoteFile>[];
    for (final item in list) {
      final type = item['Type'] as String? ?? 'blob';
      final name = (item['Path'] as String? ?? item['Name'] as String? ?? '');
      final size = (item['Size'] as num?)?.toInt() ?? 0;
      if (type != 'blob' || !_isRuntimeFile(name)) continue;
      result.add(RemoteFile(
        path: name,
        size: size,
        url:
            'https://modelscope.cn/models/${model.modelScopeRepo}/resolve/master/${_encodePath(name)}',
      ));
    }
    return result;
  }

  Future<List<RemoteFile>> _listFromHuggingFace(ModelSpec model) async {
    final uri = Uri.parse(
      'https://hf-mirror.com/api/models/${model.hfRepo}/tree/main',
    );
    final res = await _client
        .get(uri, headers: {'User-Agent': _ua})
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw DownloadException('HF mirror ${res.statusCode}');
    }
    final list = (jsonDecode(utf8.decode(res.bodyBytes)) as List)
        .cast<Map>();
    final result = <RemoteFile>[];
    for (final item in list) {
      final type = item['type'] as String? ?? 'file';
      final name = item['path'] as String? ?? '';
      final size = (item['size'] as num?)?.toInt() ?? 0;
      if (type != 'file' || !_isRuntimeFile(name)) continue;
      result.add(RemoteFile(
        path: name,
        size: size,
        url:
            'https://hf-mirror.com/${model.hfRepo}/resolve/main/${_encodePath(name)}',
      ));
    }
    return result;
  }

  String _encodePath(String value) =>
      value.split('/').map(Uri.encodeComponent).join('/');

  bool _isRuntimeFile(String name) {
    final lower = name.toLowerCase();
    final base = p.basename(lower);
    if (lower.startsWith('assets/')) return false;
    if (base == '.gitattributes') return false;
    if (base.startsWith('readme') || base.startsWith('license')) return false;
    const blocked = [
      '.md', '.png', '.jpg', '.jpeg', '.gif', '.webp', '.mp4', '.mov',
      '.pdf', '.svg', '.py', '.sh', '.zip', '.onnx', '.safetensors',
      '.bin.index', '.model',
    ];
    if (blocked.any(lower.endsWith)) return false;
    if (base == 'configuration.json' || base == 'export_args.json') {
      return false;
    }
    const allowed = [
      '.mnn', '.weight', '.mtok', '.json', '.txt', '.jinja', '.bin',
    ];
    return allowed.any(lower.endsWith) ||
        lower.contains('.mnn.weight.') ||
        lower.contains('.weight.part');
  }

  Future<void> download({
    required ModelSpec model,
    required List<RemoteFile> files,
    required String destDir,
    required void Function(DownloadProgress progress) onProgress,
    required bool Function() isCancelled,
  }) async {
    final dir = Directory(destDir);
    await dir.create(recursive: true);

    var total = 0;
    for (final f in files) {
      total += f.size;
    }
    var received = 0;
    for (final f in files) {
      final existing = File(p.join(destDir, f.path));
      if (await existing.exists() && await existing.length() == f.size) {
        received += f.size;
      }
    }
    onProgress(DownloadProgress(received: received, total: total));

    for (final f in files) {
      if (isCancelled()) throw const DownloadCancelled();
      final target = File(p.join(destDir, f.path));
      if (await target.exists() && await target.length() == f.size) {
        continue;
      }
      await target.parent.create(recursive: true);
      final part = File('${target.path}.part');
      var offset = await part.exists() ? await part.length() : 0;
      if (offset > f.size) {
        await part.delete();
        offset = 0;
      }
      received += offset;

      final request = http.Request('GET', Uri.parse(f.url))
        ..headers['User-Agent'] = _ua;
      if (offset > 0) {
        request.headers['Range'] = 'bytes=$offset-';
      }
      final response = await _client.send(request);
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw DownloadException('下载失败：${f.path} (${response.statusCode})');
      }
      final append = response.statusCode == 206 && offset > 0;
      if (!append && offset > 0) {
        // 服务端忽略了 Range，从头返回整个文件，撤销已计入的续传字节。
        received -= offset;
        offset = 0;
      }
      final sink = part.openWrite(mode: append ? FileMode.append : FileMode.write);
      var lastTick = DateTime.now();
      try {
        await for (final chunk in response.stream) {
          if (isCancelled()) {
            await sink.flush();
            await sink.close();
            throw const DownloadCancelled();
          }
          sink.add(chunk);
          received += chunk.length;
          final now = DateTime.now();
          if (now.difference(lastTick).inMilliseconds >= 120) {
            lastTick = now;
            await sink.flush();
            onProgress(DownloadProgress(
              received: received,
              total: total,
              file: f.path,
            ));
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      if (isCancelled()) throw const DownloadCancelled();

      final partLength = await part.length();
      if (f.size > 0 && partLength != f.size) {
        throw DownloadException(
          '文件大小不匹配：${f.path}，期望 ${f.size}，实际 $partLength',
        );
      }
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      onProgress(DownloadProgress(
        received: received,
        total: total,
        file: f.path,
      ));
    }

    final manifest = File(p.join(destDir, 'mnn_pocket.json'));
    await manifest.writeAsString(jsonEncode({
      'id': model.id,
      'name': model.name,
      'vendor': model.vendor,
      'paramsB': model.paramsB,
      'contextLength': model.contextLength,
      'installedAt': DateTime.now().millisecondsSinceEpoch,
    }));
  }

  void dispose() => _client.close();
}
