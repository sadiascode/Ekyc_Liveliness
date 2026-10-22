import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/camera_errors.dart';
import '../core/kyc_storage.dart';
import '../core/theme.dart';
import '../models/kyc_data.dart';
import '../services/image_quality_service.dart';
import '../services/nid_ocr_service.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/camera_cover_preview.dart';
import '../widgets/camera_error_view.dart';
import '../widgets/overlays.dart';

enum NidSide { front, back }

extension NidSideText on NidSide {
  String get title => this == NidSide.front ? 'NID front' : 'NID back';
  String get hint => this == NidSide.front
      ? 'Place the photo side of the card inside the frame'
      : 'Turn the card over and place the back inside the frame';
}

class NidCaptureScreen extends StatefulWidget {
  const NidCaptureScreen({super.key, required this.side});

  final NidSide side;

  @override
  State<NidCaptureScreen> createState() => _NidCaptureScreenState();
}

enum _Phase { camera, processing, review }

class _NidCaptureScreenState extends State<NidCaptureScreen>
    with WidgetsBindingObserver {
  /// ISO/IEC 7810 ID-1 card: 85.60 x 53.98 mm.
  static const _cardAspect = 85.6 / 53.98;

  final _ocr = NidOcrService();
  CameraController? _controller;
  bool _initializing = false;
  bool _torchOn = false;
  String? _error;
  _Phase _phase = _Phase.camera;
  NidCapture? _result;

  Size? _screen;
  Rect? _frame;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _ocr.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (c != null) {
        _controller = null;
        c.dispose();
        if (mounted) setState(() {});
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null && _error == null) _init();
    }
  }

  Future<void> _init() async {
    if (_initializing) return;
    _initializing = true;
    try {
      final cameras = await availableCameras();
      final back = cameras
              .where((c) => c.lensDirection == CameraLensDirection.back)
              .firstOrNull ??
          cameras.firstOrNull;
      if (back == null) {
        if (mounted) setState(() => _error = 'No camera found on this device.');
        return;
      }
      final c =
          CameraController(back, ResolutionPreset.veryHigh, enableAudio: false);
      await c.initialize();
      await c.setFlashMode(FlashMode.off);
      try {
        await c.setFocusMode(FocusMode.auto);
      } catch (_) {}
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _error = null;
        _torchOn = false;
      });
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = cameraErrorMessage(e));
    } finally {
      _initializing = false;
    }
  }

  Rect _frameFor(Size screen) {
    final width = screen.width * 0.88;
    return Rect.fromCenter(
      center: Offset(screen.width / 2, screen.height * 0.42),
      width: width,
      height: width / _cardAspect,
    );
  }

  Future<void> _toggleTorch() async {
    final c = _controller;
    if (c == null) return;
    final next = !_torchOn;
    await c.setFlashMode(next ? FlashMode.torch : FlashMode.off);
    setState(() => _torchOn = next);
  }

  Future<void> _capture() async {
    final c = _controller;
    final screen = _screen;
    final frame = _frame;
    final preview = c?.value.previewSize;
    if (c == null ||
        !c.value.isInitialized ||
        c.value.isTakingPicture ||
        screen == null ||
        frame == null ||
        preview == null) {
      return;
    }

    setState(() => _phase = _Phase.processing);
    try {
      final shot = await c.takePicture();
      if (_torchOn) {
        await c.setFlashMode(FlashMode.off);
        _torchOn = false;
      }

      // Map the on-screen frame into the photo, accounting for the
      // cover-fit preview cropping. A small margin keeps card edges.
      final portrait = Size(preview.height, preview.width);
      final scale = math.max(
          screen.width / portrait.width, screen.height / portrait.height);
      final shown = Size(portrait.width * scale, portrait.height * scale);
      final dx = (screen.width - shown.width) / 2;
      final dy = (screen.height - shown.height) / 2;
      final r = frame.inflate(frame.width * 0.03);

      final processed = await ImageQualityService.cropAndAssess(
        shot.path,
        left: (r.left - dx) / shown.width,
        top: (r.top - dy) / shown.height,
        width: r.width / shown.width,
        height: r.height / shown.height,
      );
      await deleteQuietly(shot.path);

      final dir = await KycStorage.dir();
      final file = File(
          '${dir.path}/nid_${widget.side.name}_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(processed.jpg, flush: true);

      final ocr = widget.side == NidSide.front
          ? await _ocr.readFront(file.path)
          : await _ocr.readBack(file.path);

      if (kDebugMode) {
        debugPrint('=== NID Capture Screen OCR Complete ===');
        debugPrint('Side: ${widget.side.name}');
        debugPrint('NID number: ${ocr.nidNumber}');
        debugPrint('English name: ${ocr.englishName}');
        debugPrint('Bangla name: ${ocr.banglaName}');
        debugPrint('Bangla father name: ${ocr.banglaFatherName}');
        debugPrint('Bangla mother name: ${ocr.banglaMotherName}');
        debugPrint('Address: ${ocr.address}');
        debugPrint('Post office: ${ocr.postOffice}');
        debugPrint('Date of birth: ${ocr.dateOfBirth}');
        if (widget.side == NidSide.back) {
          debugPrint('Back-side OCR - Blood group detected: ${ocr.bloodGroup}');
        }
      }

      if (!mounted) return;
      setState(() {
        _result = NidCapture(image: file, quality: processed.quality, ocr: ocr);
        _phase = _Phase.review;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _Phase.camera);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('The card could not be captured. Try again.')),
      );
    }
  }

  Future<void> _retake() async {
    final old = _result;
    setState(() {
      _result = null;
      _phase = _Phase.camera;
    });
    if (old != null) await deleteQuietly(old.image.path);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    if (_phase == _Phase.review && result != null) return _buildReview(result);
    return _buildCamera();
  }

  Widget _buildCamera() {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: _error != null
          ? CameraErrorView(
              message: _error!,
              onRetry: () {
                setState(() => _error = null);
                _init();
              },
              onClose: () => Navigator.of(context).pop(),
            )
          : LayoutBuilder(
              builder: (context, box) {
                final screen = box.biggest;
                final frame = _frameFor(screen);
                _screen = screen;
                _frame = frame;

                return SizedBox.expand(
                  child: Stack(
                    children: [
                      if (c != null && c.value.isInitialized)
                        Positioned.fill(
                            child: CameraCoverPreview(controller: c)),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: CardFramePainter(
                              frame: frame, color: Colors.white),
                        ),
                      ),
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              IconButton(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close,
                                    color: Colors.white),
                                tooltip: 'Close',
                              ),
                              const SizedBox(width: 4),
                              Text(
                                widget.side.title,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: c == null ? null : _toggleTorch,
                                icon: Icon(
                                    _torchOn ? Icons.flash_on : Icons.flash_off,
                                    color: Colors.white),
                                tooltip: _torchOn
                                    ? 'Turn light off'
                                    : 'Turn light on',
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 32,
                        right: 32,
                        top: frame.bottom + 24,
                        child: Text(
                          widget.side.hint,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16, height: 1.4),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 28),
                            child: Center(
                                child: _ShutterButton(
                                    onPressed: c == null ? null : _capture)),
                          ),
                        ),
                      ),
                      if (_phase == _Phase.processing)
                        const Positioned.fill(
                            child:
                                BusyOverlay(label: 'Checking image quality')),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildReview(NidCapture r) {
    final q = r.quality;
    final isFront = widget.side == NidSide.front;
    final nid = r.ocr?.nidNumber;

    return Scaffold(
      appBar: AppBar(
        title: Text('Check ${widget.side.title}'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: _cardAspect,
                child: Image.file(r.image, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 20),
            _CheckRow(
              ok: !q.isBlurry,
              text: q.isBlurry
                  ? 'Image is blurry. Hold the phone steady.'
                  : 'Image is sharp',
            ),
            _CheckRow(
              ok: !q.isTooDark && !q.isTooBright,
              text: q.isTooDark
                  ? 'Too dark. Move to a brighter place.'
                  : q.isTooBright
                      ? 'Too bright. Avoid direct light on the card.'
                      : 'Lighting is good',
            ),
            _CheckRow(
              ok: !q.hasGlare,
              text: q.hasGlare
                  ? 'Glare on the card. Tilt it slightly away from the light.'
                  : 'No glare',
            ),
            if (isFront)
              _CheckRow(
                ok: nid != null,
                soft: true,
                text: nid != null
                    ? 'NID number read: $nid'
                    : 'The NID number could not be read. Retake if the text looks unclear.',
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: q.passed ? () => Navigator.of(context).pop(r) : null,
              child: const Text('Use this photo'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _retake, child: const Text('Retake')),
          ],
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Take photo',
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          padding: const EdgeInsets.all(5),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: onPressed == null ? Colors.white38 : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.ok, required this.text, this.soft = false});

  final bool ok;
  final bool soft;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color =
        ok ? AppColors.verified : (soft ? AppColors.caution : AppColors.danger);
    final icon = ok ? Icons.check_circle : (soft ? Icons.info : Icons.cancel);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppColors.ink, fontSize: 15, height: 1.35)),
          ),
        ],
      ),
    );
  }
}
