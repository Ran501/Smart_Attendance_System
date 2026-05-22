import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// A camera preview that keeps the real camera aspect ratio.
///
/// Using [CameraPreview] directly inside an expanding Stack can stretch the
/// image on some phones, making faces look flat/wide. This widget scales the
/// preview to cover the available area without distortion and mirrors the front
/// camera so the user sees a natural selfie-style preview.
class NaturalCameraPreview extends StatelessWidget {
  final CameraController controller;
  final bool mirrorFrontCamera;

  const NaturalCameraPreview({
    super.key,
    required this.controller,
    this.mirrorFrontCamera = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenAspectRatio = constraints.maxWidth / constraints.maxHeight;
        final cameraAspectRatio = controller.value.aspectRatio;
        var scale = screenAspectRatio * cameraAspectRatio;
        if (scale < 1) scale = 1 / scale;

        Widget preview = CameraPreview(controller);
        if (mirrorFrontCamera &&
            controller.description.lensDirection == CameraLensDirection.front) {
          preview = Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(math.pi),
            child: preview,
          );
        }

        return ClipRect(
          child: Transform.scale(
            scale: scale,
            child: Center(child: preview),
          ),
        );
      },
    );
  }
}
