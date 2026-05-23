import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';

/// FacePass brand mark — always circular (no square corners).
class AppBrandLogo extends StatelessWidget {
  final double size;
  final bool elevated;
  final bool showRing;
  final Color? ringColor;

  const AppBrandLogo({
    super.key,
    this.size = 72,
    this.elevated = true,
    this.showRing = true,
    this.ringColor,
  });

  factory AppBrandLogo.splash() => const AppBrandLogo(
        size: 128,
        elevated: true,
        showRing: true,
      );

  factory AppBrandLogo.compact() => const AppBrandLogo(
        size: 64,
        elevated: true,
        showRing: true,
      );

  factory AppBrandLogo.inline({double size = 36}) => AppBrandLogo(
        size: size,
        elevated: true,
        showRing: false,
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ring = ringColor ?? scheme.primary;
    const ringThickness = 14.0;
    final outer = size + (showRing ? ringThickness * 2 : 0);
    // Logo fills the inner opening of the glow ring.
    final imageDiameter = showRing ? outer - ringThickness * 0.75 : size;

    Widget logo = _circleImage(imageDiameter, scheme, elevated: elevated);

    if (!showRing) return logo;

    return SizedBox(
      width: outer,
      height: outer,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: outer,
            height: outer,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [
                  ring.withValues(alpha: 0.15),
                  ring.withValues(alpha: 0.55),
                  Colors.white.withValues(alpha: 0.35),
                  ring.withValues(alpha: 0.45),
                  ring.withValues(alpha: 0.12),
                ],
              ),
            ),
          ),
          logo,
        ],
      ),
    );
  }

  Widget _circleImage(double diameter, ColorScheme scheme, {required bool elevated}) {
    if (!elevated) {
      return ClipOval(
        child: Image.asset(
          AppConstants.brandIconAsset,
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackIcon(diameter, scheme),
        ),
      );
    }

    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: diameter * 0.14,
            offset: Offset(0, diameter * 0.06),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        AppConstants.brandIconAsset,
        width: diameter,
        height: diameter,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackIcon(diameter, scheme),
      ),
    );
  }

  Widget _fallbackIcon(double diameter, ColorScheme scheme) {
    return Container(
      width: diameter,
      height: diameter,
      color: scheme.primaryContainer,
      alignment: Alignment.center,
      child: Icon(
        Icons.face_retouching_natural,
        size: diameter * 0.5,
        color: scheme.primary,
      ),
    );
  }
}
