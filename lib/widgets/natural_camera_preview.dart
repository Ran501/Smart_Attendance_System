import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Full-screen camera preview (no mirror flip — raw front-camera view).
class NaturalCameraPreview extends StatelessWidget {
  final CameraController controller;

  const NaturalCameraPreview({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final previewSize = controller.value.previewSize;
        if (previewSize == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final previewW = previewSize.height;
        final previewH = previewSize.width;
        final viewW = constraints.maxWidth;
        final viewH = constraints.maxHeight;
        if (viewW <= 0 || viewH <= 0) {
          return const SizedBox.shrink();
        }

        final scale = math.max(viewW / previewW, viewH / previewH);

        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            maxWidth: previewW * scale,
            maxHeight: previewH * scale,
            child: SizedBox(
              width: previewW,
              height: previewH,
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }
}
