import 'package:flutter/material.dart';

/// 模型厂商官方标识。未知厂商回退到通用内存图标。
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, required this.vendor, this.size = 40});

  final String vendor;
  final double size;

  static String? assetFor(String vendor) {
    switch (vendor) {
      case 'Alibaba MNN':
        return 'assets/logos/mnn.png';
      case 'Qwen':
        return 'assets/logos/qwen.png';
      case 'OpenBMB':
        return 'assets/logos/openbmb.png';
      case 'Tencent':
        return 'assets/logos/hunyuan.png';
      case 'Baidu':
        return 'assets/logos/baidu.png';
      case 'HuggingFace':
        return 'assets/logos/huggingface.png';
      case 'Meta':
        return 'assets/logos/meta.png';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final asset = assetFor(vendor);
    final fallback = Icon(
      Icons.memory,
      size: size * 0.55,
      color: scheme.onSurfaceVariant,
    );
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * (vendor == 'Baidu' ? 0.02 : 0.1)),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: asset == null
          ? fallback
          : Image.asset(
              asset,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}
