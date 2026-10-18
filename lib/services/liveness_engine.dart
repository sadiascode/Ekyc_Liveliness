import 'dart:math';
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum LivenessChallenge {
  blink('Blink your eyes'),
  turnLeft('Turn your head to the left'),
  turnRight('Turn your head to the right'),
  smile('Smile');

  const LivenessChallenge(this.instruction);
  final String instruction;
}

enum LivenessStage { positioning, challenge, finalPose, readyToCapture, failed }

enum FaceIssue {
  none(null),
  noFace('Place your face inside the oval'),
  multipleFaces('Only one person should be in view'),
  tooFar('Move the phone closer'),
  tooClose('Move the phone a little further away'),
  notCentered('Center your face in the oval'),
  notFacingForward('Look straight at the camera'),
  eyesClosed('Keep your eyes open');

  const FaceIssue(this.message);
  final String? message;
}

class LivenessUpdate {
  const LivenessUpdate({
    required this.stage,
    required this.issue,
    required this.completed,
    required this.total,
    this.challenge,
    this.challengeJustPassed = false,
    this.failureReason,
  });

  final LivenessStage stage;
  final FaceIssue issue;
  final int completed;
  final int total;
  final LivenessChallenge? challenge;
  final bool challengeJustPassed;
  final String? failureReason;
}

/// Pure decision logic for active liveness: a random sequence of challenges,
/// each started from a neutral pose and bounded by a timeout, with the same
/// tracked face required throughout. Feed it ML Kit faces frame by frame.
class LivenessEngine {
  LivenessEngine({
    int challengeCount = 3,
    this.challengeTimeout = const Duration(seconds: 8),
    this.sessionTimeout = const Duration(seconds: 60),
    Random? random,
  }) : challenges = (List.of(LivenessChallenge.values)
              ..shuffle(random ?? Random.secure()))
            .take(challengeCount)
            .toList(growable: false);

  /// ML Kit yaw sign relative to the user's own left/right on the front
  /// camera. If "turn left" and "turn right" feel swapped on your test
  /// devices, set this to -1.
  static const double yawSign = 1.0;

  static const double _turnDeg = 25;
  static const double _neutralYawDeg = 10;
  static const double _neutralRollDeg = 12;
  static const double _eyesOpen = 0.7;
  static const double _eyesClosed = 0.25;
  static const double _smiling = 0.85;
  static const double _notSmiling = 0.3;
  static const int _stableFramesNeeded = 6;

  final List<LivenessChallenge> challenges;
  final Duration challengeTimeout;
  final Duration sessionTimeout;
  final DateTime startedAt = DateTime.now();
  final List<String> passed = [];

  LivenessStage _stage = LivenessStage.positioning;
  int _index = 0;
  int? _trackingId;
  DateTime? _challengeStartedAt;
  bool _eyesOpenSeen = false;
  bool _eyesClosedSeen = false;
  bool _straightFaceSeen = false;
  int _stableFrames = 0;
  String? _failureReason;

  LivenessStage get stage => _stage;
  int? get trackingId => _trackingId;

  LivenessUpdate process(List<Face> faces, Size uprightImageSize) {
    if (_stage == LivenessStage.failed || _stage == LivenessStage.readyToCapture) {
      return _update();
    }

    final now = DateTime.now();
    if (now.difference(startedAt) > sessionTimeout) {
      return _fail('Time ran out. Try again.');
    }
    if (_stage == LivenessStage.challenge &&
        _challengeStartedAt != null &&
        now.difference(_challengeStartedAt!) > challengeTimeout) {
      return _fail('The prompt was not completed in time. Try again.');
    }

    if (faces.isEmpty) return _issue(FaceIssue.noFace);
    if (faces.length > 1) return _issue(FaceIssue.multipleFaces);
    final face = faces.first;

    // Same person from first challenge to final photo.
    final id = face.trackingId;
    if (id != null) {
      if (_trackingId != null && id != _trackingId && _index > 0) {
        return _fail('Keep your face in view the whole time. Try again.');
      }
      _trackingId = id;
    }

    final placement = _placementIssue(face, uprightImageSize);
    if (placement != FaceIssue.none) return _issue(placement);

    final yaw = (face.headEulerAngleY ?? 0) * yawSign;
    final roll = face.headEulerAngleZ ?? 0;
    final l = face.leftEyeOpenProbability;
    final r = face.rightEyeOpenProbability;
    final smile = face.smilingProbability ?? 0;
    final neutral = yaw.abs() < _neutralYawDeg && roll.abs() < _neutralRollDeg;
    final eyesOpen = l != null && r != null && l > _eyesOpen && r > _eyesOpen;
    final eyesClosed = l != null && r != null && l < _eyesClosed && r < _eyesClosed;

    switch (_stage) {
      case LivenessStage.positioning:
        if (!neutral) return _issue(FaceIssue.notFacingForward);
        _startChallenge();
        return _update();

      case LivenessStage.challenge:
        final current = challenges[_index];
        final done = switch (current) {
          LivenessChallenge.blink => _trackBlink(eyesOpen, eyesClosed),
          LivenessChallenge.turnLeft => yaw > _turnDeg,
          LivenessChallenge.turnRight => yaw < -_turnDeg,
          LivenessChallenge.smile => _trackSmile(smile),
        };
        if (!done) return _update();
        passed.add(current.name);
        _index++;
        // Back to neutral before the next prompt, so one pose can't satisfy two.
        _stage = _index >= challenges.length
            ? LivenessStage.finalPose
            : LivenessStage.positioning;
        _stableFrames = 0;
        return _update(justPassed: true);

      case LivenessStage.finalPose:
        if (!neutral) return _issue(FaceIssue.notFacingForward);
        if (!eyesOpen) return _issue(FaceIssue.eyesClosed);
        if (++_stableFrames >= _stableFramesNeeded) {
          _stage = LivenessStage.readyToCapture;
        }
        return _update();

      case LivenessStage.readyToCapture:
      case LivenessStage.failed:
        return _update();
    }
  }

  void _startChallenge() {
    _stage = LivenessStage.challenge;
    _challengeStartedAt = DateTime.now();
    _eyesOpenSeen = false;
    _eyesClosedSeen = false;
    _straightFaceSeen = false;
  }

  /// Requires open -> closed -> open, so a still photo can't pass.
  bool _trackBlink(bool open, bool closed) {
    if (open && !_eyesClosedSeen) _eyesOpenSeen = true;
    if (closed && _eyesOpenSeen) _eyesClosedSeen = true;
    return open && _eyesOpenSeen && _eyesClosedSeen;
  }

  /// Requires a straight face first, so someone already smiling can't pass.
  bool _trackSmile(double smile) {
    if (smile < _notSmiling) _straightFaceSeen = true;
    return _straightFaceSeen && smile > _smiling;
  }

  FaceIssue _placementIssue(Face face, Size size) {
    final box = face.boundingBox;
    final widthRatio = box.width / size.width;
    if (widthRatio < 0.30) return FaceIssue.tooFar;
    if (widthRatio > 0.85) return FaceIssue.tooClose;
    final cx = box.center.dx / size.width;
    final cy = box.center.dy / size.height;
    if (cx < 0.25 || cx > 0.75 || cy < 0.2 || cy > 0.75) {
      return FaceIssue.notCentered;
    }
    return FaceIssue.none;
  }

  LivenessUpdate _issue(FaceIssue issue) {
    _stableFrames = 0;
    return _update(issue: issue);
  }

  LivenessUpdate _fail(String reason) {
    _stage = LivenessStage.failed;
    _failureReason = reason;
    return _update();
  }

  LivenessUpdate _update({FaceIssue issue = FaceIssue.none, bool justPassed = false}) {
    return LivenessUpdate(
      stage: _stage,
      issue: issue,
      completed: _index,
      total: challenges.length,
      challenge: _index < challenges.length ? challenges[_index] : null,
      challengeJustPassed: justPassed,
      failureReason: _failureReason,
    );
  }
}
