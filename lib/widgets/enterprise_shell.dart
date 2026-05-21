import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class EnterpriseScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final bool safeArea;

  const EnterpriseScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.safeArea = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary.withValues(alpha: 0.14),
                  scheme.surface,
                  scheme.secondary.withValues(alpha: 0.10),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: -120,
          right: -90,
          child: _GlowBall(size: 260, color: scheme.primary.withValues(alpha: 0.16)),
        ),
        Positioned(
          bottom: -160,
          left: -90,
          child: _GlowBall(size: 300, color: scheme.secondary.withValues(alpha: 0.13)),
        ),
        Positioned.fill(
          child: CustomPaint(painter: _BhutanPatternPainter(scheme.outlineVariant.withValues(alpha: 0.10))),
        ),
        safeArea ? SafeArea(child: body) : body,
      ],
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      body: bg,
    );
  }
}

class _GlowBall extends StatelessWidget {
  final double size;
  final Color color;
  const _GlowBall({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30), child: const SizedBox()),
    );
  }
}

class _BhutanPatternPainter extends CustomPainter {
  final Color color;
  _BhutanPatternPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (double y = 40; y < size.height; y += 72) {
      for (double x = -20; x < size.width; x += 72) {
        final path = Path()
          ..moveTo(x + 18, y)
          ..quadraticBezierTo(x + 36, y + 24, x + 54, y)
          ..quadraticBezierTo(x + 36, y + 24, x + 18, y + 48)
          ..quadraticBezierTo(x + 36, y + 24, x + 54, y + 48);
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BhutanPatternPainter oldDelegate) => oldDelegate.color != color;
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Color? color;
  final VoidCallback? onTap;
  final Border? border;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin,
    this.radius = 26,
    this.color,
    this.onTap,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? scheme.surface.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.66 : 0.78),
            borderRadius: BorderRadius.circular(radius),
            border: border ?? Border.all(color: scheme.outlineVariant.withValues(alpha: 0.50)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.24 : 0.06),
                blurRadius: 26,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
    final wrapped = onTap == null
        ? card
        : Material(
            color: Colors.transparent,
            child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, child: card),
          );
    return Padding(padding: margin ?? EdgeInsets.zero, child: wrapped);
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const SectionTitle({super.key, required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class StatusPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const StatusPill({super.key, required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
        ],
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const MetricTile({super.key, required this.label, required this.value, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: c, size: 22),
          ),
          const SizedBox(height: 16),
          Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double minItemWidth;
  final double gap;
  final double childAspectRatio;

  const ResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 220,
    this.gap = 14,
    this.childAspectRatio = 1.25,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final count = math.max(1, (width / minItemWidth).floor());
        return GridView.count(
          crossAxisCount: count,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: gap,
          crossAxisSpacing: gap,
          childAspectRatio: childAspectRatio,
          children: children,
        );
      },
    );
  }
}

class AttendanceLiquidGauge extends StatelessWidget {
  final double percentage;
  final double size;
  final bool compact;

  const AttendanceLiquidGauge({super.key, required this.percentage, this.size = 120, this.compact = false});

  Color _riskColor() {
    if (percentage >= 90) return const Color(0xFF10B981);
    if (percentage >= 80) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  String get riskLabel {
    if (percentage >= 90) return 'Safe';
    if (percentage >= 80) return 'Watch';
    return 'Risk';
  }

  @override
  Widget build(BuildContext context) {
    final color = _riskColor();
    final pct = percentage.clamp(0, 100) / 100;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: pct),
      duration: 900.ms,
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return SizedBox(
          width: size,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: size,
                height: compact ? size * 0.74 : size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(compact ? 28 : size / 2),
                  border: Border.all(color: color.withValues(alpha: 0.55), width: 2),
                  color: color.withValues(alpha: 0.07),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: value,
                        widthFactor: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [color.withValues(alpha: 0.55), color],
                            ),
                          ),
                        ),
                      ),
                    ),
                    CustomPaint(size: Size(size, compact ? size * 0.74 : size), painter: _WavePainter(color, value)),
                    Text(
                      '${percentage.toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 10),
                StatusPill(label: riskLabel, icon: Icons.shield_outlined, color: color),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  final Color color;
  final double value;
  _WavePainter(this.color, this.value);

  @override
  void paint(Canvas canvas, Size size) {
    if (value <= 0) return;
    final y = size.height * (1 - value);
    final paint = Paint()..color = color.withValues(alpha: 0.30);
    final path = Path()..moveTo(0, y);
    for (double x = 0; x <= size.width; x++) {
      path.lineTo(x, y + math.sin((x / size.width * math.pi * 2)) * 6);
    }
    path
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) => oldDelegate.value != value || oldDelegate.color != color;
}
