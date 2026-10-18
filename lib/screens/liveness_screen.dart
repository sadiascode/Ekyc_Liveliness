import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../core/camera_errors.dart';
import '../core/kyc_storage.dart';
import '../core/theme.dart';
import '../models/kyc_data.dart';
import '../services/liveness_engine.dart';
import '../utils/camera_image_converter.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/camera_cover_preview.dart';
import '../widgets/camera_error_view.dart';
import '../widgets/overlays.dart';

class LivenessScreen extends StatefulWidget {
  const LivenessScreen({super.key});

  @override
  State<LivenessScreen> createState() => _LivenessScreenState();
}

class _LivenessScreenState extends State<LivenessScreen> with WidgetsBindingObserver {
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true, // eye-open and smile probabilities
      enableTracking: true, // same-face check across the session
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.2,
    ),
  );

  CameraController? _controller;
  LivenessEngine _engine = LivenessEngine();
  LivenessUpdate? _update;
  bool _initializing = false;
  bool _processing = false;
  bool _capturing = false;
  bool _backgrounded = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    _detector.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (_controller != null) {
        _backgrounded = true;
        _disposeCamera();
        if (mounted) setState(() {});
      }
    } else if (state == AppLifecycleState.resumed && _backgrounded) {
      _backgrounded = false;
      // Never resume a half-finished session.
      _restart(notice: 'Verification restarted because the app left the screen.');
    }
  }

  Future<void> _disposeCamera() async {
    final c = _controller;
    _controller = null;
    if (c == null) return;
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    await c.dispose();
  }

  Future<void> _init() async {
    if (_initializing) return;
    _initializing = true;
    try {
      final cameras = await availableCameras();
      final front = cameras.where((c) => c.lensDirection == CameraLensDirection.front).firstOrNull;
      if (front == null) {
        if (mounted) setState(() => _error = 'This device has no front camera.');
        return;
      }
      final c = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _error = null;
      });
      await c.startImageStream(_onFrame);
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = cameraErrorMessage(e));
    } finally {
      _initializing = false;
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    final c = _controller;
    if (_processing || _capturing || c == null) return;
    if (_engine.stage == LivenessStage.failed) return;
    _processing = true;
    try {
      final frame = CameraImageConverter.convert(image, c);
      if (frame == null) return;
      final faces = await _detector.processImage(frame.inputImage);
      if (!mounted) return;

      final update = _engine.process(faces, frame.uprightSize);
      if (update.challengeJustPassed) HapticFeedback.mediumImpact();
      setState(() {
        _update = update;
        if (update.stage == LivenessStage.challenge) _notice = null;
      });
      if (update.stage == LivenessStage.readyToCapture) unawaited(_capture());
    } catch (e) {
      debugPrint('Liveness frame error: $e');
    } finally {
      _processing = false;
    }
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || _capturing) return;
    setState(() => _capturing = true);

    String? shotPath;
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
      final shot = await c.takePicture();
      shotPath = shot.path;

      // Re-check the actual saved photo, not just the stream frames.
      final faces = await _detector.processImage(InputImage.fromFilePath(shot.path));
      if (!_isAcceptableSelfie(faces)) {
        await deleteQuietly(shot.path);
        if (mounted) {
          await _restart(notice: 'The photo was not clear. Keep still, look at the camera, eyes open.');
        }
        return;
      }

      final dir = await KycStorage.dir();
      final saved = await File(shot.path).copy('${dir.path}/selfie_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await deleteQuietly(shot.path);
      if (!mounted) return;

      Navigator.of(context).pop(
        LivenessResult(
          selfie: saved,
          challenges: List.unmodifiable(_engine.passed),
          startedAt: _engine.startedAt,
          completedAt: DateTime.now(),
          trackingId: _engine.trackingId,
        ),
      );
    } on CameraException catch (_) {
      if (shotPath != null) await deleteQuietly(shotPath);
      if (mounted) await _restart(notice: 'The camera could not take the photo. Try again.');
    }
  }

  bool _isAcceptableSelfie(List<Face> faces) {
    if (faces.length != 1) return false;
    final f = faces.first;
    return (f.leftEyeOpenProbability ?? 0) > 0.5 &&
        (f.rightEyeOpenProbability ?? 0) > 0.5 &&
        (f.headEulerAngleY ?? 90).abs() < 15;
  }

  Future<void> _restart({String? notice}) async {
    if (!mounted) return;
    setState(() {
      _engine = LivenessEngine(); // fresh random challenge order every attempt
      _update = null;
      _capturing = false;
      _notice = notice;
    });
    final c = _controller;
    if (c == null) {
      await _init();
    } else if (!c.value.isStreamingImages) {
      await c.startImageStream(_onFrame);
    }
  }

  (String, String?) _prompt(LivenessUpdate? u) {
    if (u == null) return ('Position your face in the oval', _notice);
    if (_capturing) return ('Hold still', null);
    final issue = u.issue.message;
    return switch (u.stage) {
      LivenessStage.positioning => (
          u.completed == 0 ? 'Look straight at the camera' : 'Good. Now look straight ahead',
          issue ?? _notice,
        ),
      LivenessStage.challenge => (u.challenge!.instruction, issue),
      LivenessStage.finalPose => ('Look straight at the camera', issue),
      LivenessStage.readyToCapture => ('Hold still', null),
      LivenessStage.failed => ('Verification stopped', u.failureReason),
    };
  }

  Color _ringColor(LivenessUpdate? u) {
    if (u == null) return Colors.white;
    if (u.stage == LivenessStage.failed) return AppColors.danger;
    return u.issue == FaceIssue.none ? Colors.white : AppColors.caution;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: CameraErrorView(
          message: _error!,
          onRetry: () {
            setState(() => _error = null);
            _init();
          },
          onClose: () => Navigator.of(context).pop(),
        ),
      );
    }

    final c = _controller;
    final u = _update;
    final failed = u?.stage == LivenessStage.failed;
    final total = _engine.challenges.length;
    final completed = u?.completed ?? 0;
    final (title, detail) = _prompt(u);

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest;
          final ovalWidth = math.min(size.width * 0.72, 320.0);
          final oval = Rect.fromCenter(
            center: Offset(size.width / 2, size.height * 0.40),
            width: ovalWidth,
            height: ovalWidth * 1.32,
          );

          return SizedBox.expand(
            child: Stack(
            children: [
              if (c != null && c.value.isInitialized)
                Positioned.fill(child: CameraCoverPreview(controller: c)),
              Positioned.fill(
                child: CustomPaint(
                  painter: FaceOvalPainter(
                    oval: oval,
                    total: total,
                    completed: completed,
                    highlight: _ringColor(u),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: Colors.white),
                        tooltip: 'Close',
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Live selfie',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 28,
                right: 28,
                top: oval.bottom + 32,
                child: Semantics(
                  liveRegion: true,
                  child: Column(
                    children: [
                      if (!failed)
                        Text(
                          'Step ${math.min(completed + 1, total)} of $total',
                          style: const TextStyle(color: Colors.white60, fontSize: 14),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                      if (detail != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          detail,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: failed ? Colors.white70 : AppColors.caution,
                            fontSize: 15,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (failed)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    minimum: const EdgeInsets.only(bottom: 20),
                    child: FilledButton(onPressed: () => _restart(), child: const Text('Try again')),
                  ),
                ),
              if (_capturing) const Positioned.fill(child: BusyOverlay(label: 'Checking photo')),
            ],
          ),
          );
        },
      ),
    );
  }
}
