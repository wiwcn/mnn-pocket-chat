import 'dart:convert';
import 'dart:io';

import 'package:mnn_pocket_chat/core/models.dart';
import 'package:mnn_pocket_chat/services/model_downloader.dart';

void main(List<String> args) async {
  final full = args.contains('--full');
  final proxy = Platform.environment['https_proxy'] ??
      Platform.environment['HTTPS_PROXY'] ??
      Platform.environment['http_proxy'] ??
      Platform.environment['HTTP_PROXY'];
  if (proxy != null && proxy.isNotEmpty) {
    final uri = Uri.parse(proxy);
    HttpOverrides.global = _ProxyOverrides('${uri.host}:${uri.port}');
  }

  final raw = jsonDecode(File('assets/models.json').readAsStringSync()) as List;
  final catalog = raw
      .map((e) => ModelSpec.fromJson((e as Map).cast<String, dynamic>()))
      .toList();
  final model = catalog.firstWhere((m) => m.id == 'MNN-Pocket-0.3B-MNN');

  final downloader = ModelDownloader();
  final files = await downloader.listFiles(model);
  stdout.writeln('Pocket 运行文件 ${files.length} 个：');
  for (final f in files) {
    stdout.writeln('  ${f.path.padRight(24)} ${f.size}');
  }
  final total = files.fold<int>(0, (sum, f) => sum + f.size);
  stdout.writeln('合计 $total 字节');

  if (files.any((f) => f.path.contains('.safetensors'))) {
    stderr.writeln('FAIL: 出现 safetensors，说明选中了错误仓库');
    exit(1);
  }
  for (final required in ['config.json', 'llm_config.json', 'llm.mnn',
      'llm.mnn.weight', 'tokenizer.mtok']) {
    if (!files.any((f) => f.path == required)) {
      stderr.writeln('FAIL: 缺少 $required');
      exit(1);
    }
  }
  stdout.writeln('结构校验通过');

  if (!full) return;

  final dir = Directory('/tmp/pocket_verify/models/${model.id}');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  final watch = Stopwatch()..start();
  var lastPct = -1;
  await downloader.download(
    model: model,
    files: files,
    destDir: dir.path,
    onProgress: (p) {
      final pct = (p.fraction * 100).floor();
      if (pct != lastPct) {
        lastPct = pct;
        stdout.writeln(
            '  下载 $pct%  ${(p.received / 1024 / 1024).toStringAsFixed(1)} MB');
      }
    },
    isCancelled: () => false,
  );
  stdout.writeln('下载耗时 ${watch.elapsed.inSeconds}s');

  var ok = true;
  for (final f in files) {
    final file = File('${dir.path}/${f.path}');
    final size = file.existsSync() ? file.lengthSync() : -1;
    if (size != f.size) {
      stderr.writeln('FAIL: ${f.path} 大小 $size != ${f.size}');
      ok = false;
    }
  }
  final manifest = File('${dir.path}/mnn_pocket.json');
  stdout.writeln('清单文件: ${manifest.existsSync()}');
  stdout.writeln(ok ? 'PASS: 所有文件完整' : 'FAIL');
  if (!ok) exit(1);
}

class _ProxyOverrides extends HttpOverrides {
  _ProxyOverrides(this.proxy);
  final String proxy;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (uri) => 'PROXY $proxy';
    return client;
  }
}
