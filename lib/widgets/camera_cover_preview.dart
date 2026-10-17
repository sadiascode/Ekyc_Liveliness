import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Fills its parent with the camera preview (like BoxFit.cover), portrait.
class CameraCoverPreview extends StatelessWidget {
  const CameraCoverPreview({super.key, required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.previewSize;
    if (size == null) return const SizedBox.shrink();
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.height,
          height: size.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}
