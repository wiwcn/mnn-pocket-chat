import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/debug_log.dart';
import '../../services/system_links.dart';
import '../../state/app_store.dart';

/// 调试日志查看/导出页。日志落盘在应用私有目录，可复制或分享出去分析闪退。
class DebugView extends StatefulWidget {
  const DebugView({super.key, required this.store});

  final AppStore store;

  @override
  State<DebugView> createState() => _DebugViewState();
}

class _DebugViewState extends State<DebugView> {
  String _content = '正在读取…';
  String _path = '—';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final content = await debugLog.read();
    final f = await debugLog.file;
    if (!mounted) return;
    setState(() {
      _content = content;
      _path = f?.path ?? '不可用';
      _loading = false;
    });
  }

  Future<void> _clear() async {
    await debugLog.clear();
    await _reload();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _content));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('日志已复制到剪贴板')),
    );
  }

  Future<void> _share() async {
    final f = await debugLog.file;
    if (f == null || !await f.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('日志文件不可用')),
      );
      return;
    }
    await SystemLinks.shareFile(f.path, mimeType: 'text/plain');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('调试日志'),
        leading: IconButton(
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '复制全部',
            onPressed: _copy,
            icon: const Icon(Icons.copy_all),
          ),
          IconButton(
            tooltip: '分享日志文件',
            onPressed: _share,
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            tooltip: '清空',
            onPressed: _clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: scheme.surfaceContainerLow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '记录模型加载、生成、下载与错误。崩溃前会先写入检查点，'
                  '下次启动可在此查看最后一次操作的日志。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'debugLog 开关：${debugLog.enabled ? '开启' : '关闭'} · 路径 $_path',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      _content.isEmpty ? '（暂无日志）' : _content,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
