import 'dart:math' as math;

import 'package:flutter/material.dart';

const double kPagePadding = 20;
const double kCardRadius = 26;

/// 纯色页面背景，仅在顶部叠加一层极淡的 primaryContainer 渐变。
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.26],
          colors: [
            Color.alphaBlend(
              scheme.primaryContainer.withValues(alpha: 0.06),
              scheme.surface,
            ),
            scheme.surface,
          ],
        ),
      ),
      child: child,
    );
  }
}

class SpringScale extends StatefulWidget {
  const SpringScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  @override
  State<SpringScale> createState() => _SpringScaleState();
}

class _SpringScaleState extends State<SpringScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null
          ? null
          : (_) {
              setState(() => _pressed = true);
            },
      onTapCancel: widget.onTap == null
          ? null
          : () {
              setState(() => _pressed = false);
            },
      onTapUp: widget.onTap == null
          ? null
          : (_) {
              setState(() => _pressed = false);
              widget.onTap!.call();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// 页面大标题 + 副标题，右侧可放置操作按钮。
class PageTitle extends StatelessWidget {
  const PageTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.fontSize = 34,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: text.displaySmall?.copyWith(
                  fontSize: fontSize,
                  letterSpacing: -0.8,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing!,
        ],
      ],
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 2, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 白底分组卡片：浅描边、大圆角、几乎无阴影。
class GroupCard extends StatelessWidget {
  const GroupCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.color,
    this.radius = kCardRadius,
    this.border = true,
    this.onTap,
    this.clip = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;
  final bool border;
  final VoidCallback? onTap;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = BorderRadius.circular(radius);
    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? scheme.surfaceContainerLowest,
        borderRadius: shape,
        border: border
            ? Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5))
            : null,
      ),
      child: Padding(padding: padding, child: child),
    );
    if (clip) {
      card = ClipRRect(borderRadius: shape, child: card);
    }
    if (onTap == null) return card;
    return SpringScale(onTap: onTap, scale: 0.99, child: card);
  }
}

/// 分组卡片内部的分隔线，左右留出内容边距。
class GroupDivider extends StatelessWidget {
  const GroupDivider({super.key, this.indent = 16, this.endIndent = 16});

  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, indent: indent, endIndent: endIndent);
  }
}

/// 圆形图标头像：primaryContainer 底 + onPrimaryContainer 图标。
class RoundIcon extends StatelessWidget {
  const RoundIcon({
    super.key,
    required this.icon,
    this.size = 44,
    this.iconSize = 22,
    this.background,
    this.foreground,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? scheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: iconSize,
        color: foreground ?? scheme.onPrimaryContainer,
      ),
    );
  }
}

/// 小号信息胶囊，用于卡片内的元数据。
class SoftPill extends StatelessWidget {
  const SoftPill({
    super.key,
    required this.label,
    this.icon,
    this.background,
    this.foreground,
  });

  final String label;
  final IconData? icon;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = foreground ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background ?? scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RoundIcon(icon: icon, size: 72, iconSize: 32),
            const SizedBox(height: 18),
            Text(title, style: text.titleMedium),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (action != null) ...[
              const SizedBox(height: 18),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

Color hexColor(String hex) {
  final value = hex.replaceAll('#', '');
  final buffer = StringBuffer('FF');
  if (value.length == 6) buffer.write(value);
  return Color(int.parse(buffer.toString(), radix: 16));
}

double clampDouble(num value, double min, double max) =>
    math.min(max, math.max(min, value.toDouble()));
