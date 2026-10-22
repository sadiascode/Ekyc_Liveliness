import 'dart:io';

/// Result of the on-device image quality check for an NID photo.
class QualityReport {
  const QualityReport({
    required this.sharpness,
    required this.brightness,
    required this.glareRatio,
    required this.isBlurry,
    required this.isTooDark,
    required this.isTooBright,
    required this.hasGlare,
  });

  final double sharpness; // Laplacian variance
  final double brightness; // mean luminance 0-255
  final double glareRatio; // share of blown-out pixels
  final bool isBlurry;
  final bool isTooDark;
  final bool isTooBright;
  final bool hasGlare;

  bool get passed => !isBlurry && !isTooDark && !isTooBright && !hasGlare;
}

/// Text read from the NID front. Always let the officer confirm it.
class NidOcrData {
  const NidOcrData({
    required this.rawText,
    this.nidNumber,
    this.dateOfBirth,
    this.name,
    this.banglaName,
    this.englishName,
    this.banglaFatherName,
    this.banglaMotherName,
    this.address,
    this.postOffice,
    this.bloodGroup,
    this.looksLikeNidFront = false,
  });

  final String rawText;
  final String? nidNumber;
  final String? dateOfBirth; // yyyy-MM-dd
  final String? name; // Legacy field, kept for backward compatibility
  final String? banglaName; // Name in Bengali script
  final String? englishName; // Name in English script
  final String? banglaFatherName; // Father's name in Bengali script
  final String? banglaMotherName; // Mother's name in Bengali script
  final String? address; // Address in Bengali script
  final String? postOffice; // Post Office in Bengali script
  final String? bloodGroup;
  final bool looksLikeNidFront;
}

class NidCapture {
  const NidCapture({required this.image, required this.quality, this.ocr});

  final File image;
  final QualityReport quality;
  final NidOcrData? ocr;
}

class LivenessResult {
  const LivenessResult({
    required this.selfie,
    required this.challenges,
    required this.startedAt,
    required this.completedAt,
    this.trackingId,
  });

  final File selfie;
  final List<String> challenges;
  final DateTime startedAt;
  final DateTime completedAt;
  final int? trackingId;

  Map<String, dynamic> toJson() => {
        'method': 'active_challenge_response',
        'challenges': challenges,
        'started_at': startedAt.toUtc().toIso8601String(),
        'completed_at': completedAt.toUtc().toIso8601String(),
        'duration_ms': completedAt.difference(startedAt).inMilliseconds,
        'platform': Platform.operatingSystem,
      };
}

class KycData {
  NidCapture? front;
  NidCapture? back;
  LivenessResult? liveness;

  int get completedSteps =>
      [front, back, liveness].where((e) => e != null).length;
  bool get isComplete => completedSteps == 3;
  bool get hasAny => completedSteps > 0;
}
