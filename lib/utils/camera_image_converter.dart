import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class ConvertedFrame {
  const ConvertedFrame(this.inputImage, this.uprightSize);
  final InputImage inputImage;

  /// Image size after rotation; ML Kit face boxes are in this space.
  final Size uprightSize;
}

/// Turns a camera stream frame into an ML Kit InputImage with the right
/// rotation. Handles both NV21 (1 plane) and YUV_420_888 (3 planes) on Android.
class CameraImageConverter {
  static const _deviceRotation = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  static ConvertedFrame? convert(CameraImage image, CameraController controller) {
    final camera = controller.description;
    final sensor = camera.sensorOrientation;

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensor);
    } else {
      final device = _deviceRotation[controller.value.deviceOrientation];
      if (device == null) return null;
      final degrees = camera.lensDirection == CameraLensDirection.front
          ? (sensor + device) % 360
          : (sensor - device + 360) % 360;
      rotation = InputImageRotationValue.fromRawValue(degrees);
    }
    if (rotation == null) return null;

    final Uint8List bytes;
    final int bytesPerRow;
    final InputImageFormat format;

    if (Platform.isAndroid) {
      if (image.planes.length == 1) {
        bytes = image.planes.first.bytes;
        bytesPerRow = image.planes.first.bytesPerRow;
      } else if (image.planes.length == 3) {
        bytes = _yuv420ToNv21(image);
        bytesPerRow = image.width;
      } else {
        return null;
      }
      format = InputImageFormat.nv21;
    } else {
      if (image.planes.length != 1) return null;
      bytes = image.planes.first.bytes;
      bytesPerRow = image.planes.first.bytesPerRow;
      format = InputImageFormat.bgra8888;
    }

    final size = Size(image.width.toDouble(), image.height.toDouble());
    final sideways = rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;

    return ConvertedFrame(
      InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: size,
          rotation: rotation,
          format: format,
          bytesPerRow: bytesPerRow,
        ),
      ),
      sideways ? Size(size.height, size.width) : size,
    );
  }

  static Uint8List _yuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final y = image.planes[0];
    final u = image.planes[1];
    final v = image.planes[2];
    final out = Uint8List(width * height + 2 * (width ~/ 2) * (height ~/ 2));

    var i = 0;
    for (var row = 0; row < height; row++) {
      out.setRange(i, i + width, y.bytes, row * y.bytesPerRow);
      i += width;
    }

    final uPixel = u.bytesPerPixel ?? 1;
    final vPixel = v.bytesPerPixel ?? 1;
    for (var row = 0; row < height ~/ 2; row++) {
      for (var col = 0; col < width ~/ 2; col++) {
        out[i++] = v.bytes[row * v.bytesPerRow + col * vPixel];
        out[i++] = u.bytes[row * u.bytesPerRow + col * uPixel];
      }
    }
    return out;
  }
}
