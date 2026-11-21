import 'dart:math' as math;

String formatBytes(int bytes, {int decimals = 1}) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  final i = (math.log(bytes) / math.log(1024)).floor().clamp(0, units.length - 1);
  final value = bytes / math.pow(1024, i);
  return '${value.toStringAsFixed(i == 0 ? 0 : decimals)} ${units[i]}';
}

String formatSpeed(double tps) {
  if (tps <= 0) return '—';
  if (tps >= 100) return '${tps.round()} tok/s';
  return '${tps.toStringAsFixed(1)} tok/s';
}

String relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1) return '${diff.inHours} 小时前';
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  return '${time.month}/${time.day}';
}

String shorten(String text, [int max = 28]) {
  final clean = text.replaceAll('\n', ' ').trim();
  if (clean.length <= max) return clean;
  return '${clean.substring(0, max)}…';
}
