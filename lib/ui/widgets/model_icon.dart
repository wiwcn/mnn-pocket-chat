import 'package:flutter/material.dart';

/// Name-based model brand resolution, adapted from Kelivo's BrandAssets.
///
/// Icons are resolved from the model name/vendor at runtime instead of a
/// per-model lookup table. Unknown models fall back to a tinted initial.
class ModelBrand {
  const ModelBrand({
    required this.group,
    required this.asset,
    required this.pattern,
  });

  final String group;
  final String asset;
  final RegExp pattern;

  static ModelBrand? resolve({required String name, String vendor = ''}) {
    for (final candidate in [name, vendor]) {
      final key = candidate.trim().toLowerCase();
      if (key.isEmpty) continue;
      for (final brand in brands) {
        if (brand.pattern.hasMatch(key)) return brand;
      }
    }
    return null;
  }

  static List<String> get assets => [
        for (final brand in brands) brand.asset,
      ];

  static final List<ModelBrand> brands = <ModelBrand>[
    ModelBrand(
      group: 'MNN',
      asset: 'assets/logos/mnn.png',
      pattern: RegExp(r'mnn|pocket|alibaba'),
    ),
    ModelBrand(
      group: 'Qwen',
      asset: 'assets/logos/qwen.png',
      pattern: RegExp(r'qwen|qwq|qvq'),
    ),
    ModelBrand(
      group: 'Hunyuan',
      asset: 'assets/logos/hunyuan.png',
      pattern: RegExp(r'hunyuan|混元'),
    ),
    ModelBrand(
      group: 'MiniCPM',
      asset: 'assets/logos/openbmb.png',
      pattern: RegExp(r'minicpm|openbmb'),
    ),
    ModelBrand(
      group: 'ERNIE',
      asset: 'assets/logos/baidu.png',
      pattern: RegExp(r'ernie|文心|baidu|paddle'),
    ),
    ModelBrand(
      group: 'SmolLM',
      asset: 'assets/logos/huggingface.png',
      pattern: RegExp(r'smollm|huggingface'),
    ),
    ModelBrand(
      group: 'MobileLLM',
      asset: 'assets/logos/meta.png',
      pattern: RegExp(r'mobilellm|llama|meta'),
    ),
  ];
}

/// Circular model avatar: tinted background, centered brand mark, and an
/// initial-letter fallback for unrecognized models.
class ModelIcon extends StatelessWidget {
  const ModelIcon({
    super.key,
    required this.name,
    this.vendor = '',
    this.size = 40,
  });

  final String name;
  final String vendor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final brand = ModelBrand.resolve(name: name, vendor: vendor);
    final fallback = Text(
      name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase(),
      style: TextStyle(
        color: scheme.primary,
        fontSize: size * .43,
        fontWeight: FontWeight.w600,
      ),
    );
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: dark ? .18 : .10),
        shape: BoxShape.circle,
      ),
      child: brand == null
          ? fallback
          : Padding(
              padding: EdgeInsets.all(size * .2),
              child: Image.asset(
                brand.asset,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => fallback,
              ),
            ),
    );
  }
}
