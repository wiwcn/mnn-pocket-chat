import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 从相册选择一张图片并复制到应用私有目录，返回绝对路径。
/// 用户取消选择或读取失败时返回 null。
Future<String?> pickAndStoreImage() async {
  try {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      imageQuality: 88,
    );
    if (picked == null) return null;

    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'attachments'));
    await dir.create(recursive: true);

    String two(int value) => value.toString().padLeft(2, '0');
    final now = DateTime.now();
    final stamp = '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final ext = p.extension(picked.path).isEmpty
        ? '.jpg'
        : p.extension(picked.path);

    var target = File(p.join(dir.path, '$stamp$ext'));
    var index = 1;
    while (await target.exists()) {
      target = File(p.join(dir.path, '${stamp}_$index$ext'));
      index++;
    }
    await File(picked.path).copy(target.path);
    return target.path;
  } catch (_) {
    return null;
  }
}
