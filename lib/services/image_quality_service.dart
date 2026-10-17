import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/kyc_data.dart';

class CardCropResult {
  const CardCropResult(this.jpg, this.quality);
  final Uint8List jpg;
  final QualityReport quality;
}

/// Crops the card out of the full photo and checks blur, exposure and glare.
/// Heavy pixel work runs in a background isolate so the UI never stutters.
class ImageQualityService {
  // Tune these on your target devices.
  static const double blurThreshold = 80;
  static const double minBrightness = 60;
  static const double maxBrightness = 215;
  static const double maxGlareRatio = 0.06;

  /// [left], [top], [width], [height] are fractions (0-1) of the upright photo.
  static Future<CardCropResult> cropAndAssess(
    String path, {
    required double left,
    required double top,
    required double width,
    required double height,
  }) async {
    final bytes = await File(path).readAsBytes();
    return Isolate.run(() => _process(bytes, left, top, width, height));
  }
}

CardCropResult _process(
  Uint8List bytes,
  double fl,
  double ft,
  double fw,
  double fh,
) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Unreadable image');
  final image = img.bakeOrientation(decoded);

  final x = (image.width * fl).round().clamp(0, image.width - 1).toInt();
  final y = (image.height * ft).round().clamp(0, image.height - 1).toInt();
  final w = (image.width * fw).round().clamp(1, image.width - x).toInt();
  final h = (image.height * fh).round().clamp(1, image.height - y).toInt();

  final card = img.copyCrop(image, x: x, y: y, width: w, height: h);
  final quality = _assess(card);
  return CardCropResult(
    Uint8List.fromList(img.encodeJpg(card, quality: 92)),
    quality,
  );
}

QualityReport _assess(img.Image card) {
  final small = img.grayscale(img.copyResize(card, width: 500));
  final w = small.width;
  final h = small.height;
  final lum = Float64List(w * h);

  var sum = 0.0;
  var blown = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final l = small.getPixel(x, y).r.toDouble();
      lum[y * w + x] = l;
      sum += l;
      if (l >= 250) blown++;
    }
  }
  final mean = sum / (w * h);
  final glare = blown / (w * h);

  // Variance of the Laplacian: low values mean few sharp edges, i.e. blur.
  var lSum = 0.0;
  var lSq = 0.0;
  var n = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final v = lum[i - w] + lum[i + w] + lum[i - 1] + lum[i + 1] - 4 * lum[i];
      lSum += v;
      lSq += v * v;
      n++;
    }
  }
  final lMean = lSum / n;
  final variance = lSq / n - lMean * lMean;

  return QualityReport(
    sharpness: variance,
    brightness: mean,
    glareRatio: glare,
    isBlurry: variance < ImageQualityService.blurThreshold,
    isTooDark: mean < ImageQualityService.minBrightness,
    isTooBright: mean > ImageQualityService.maxBrightness,
    hasGlare: glare > ImageQualityService.maxGlareRatio,
  );
}
