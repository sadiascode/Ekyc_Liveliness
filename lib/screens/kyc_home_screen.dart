import 'dart:io';

import 'package:flutter/material.dart';

import '../core/kyc_storage.dart';
import '../core/theme.dart';
import '../models/kyc_data.dart';
import 'liveness_screen.dart';
import 'nid_capture_screen.dart';
import 'review_screen.dart';

class KycHomeScreen extends StatefulWidget {
  const KycHomeScreen({super.key});

  @override
  State<KycHomeScreen> createState() => _KycHomeScreenState();
}

class _KycHomeScreenState extends State<KycHomeScreen> {
  KycData _data = KycData();

  Future<void> _captureNid(NidSide side) async {
    final result = await Navigator.of(context).push<NidCapture>(
      MaterialPageRoute(builder: (_) => NidCaptureScreen(side: side)),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (side == NidSide.front) {
        _data.front = result;
      } else {
        _data.back = result;
      }
    });
  }

  Future<void> _captureSelfie() async {
    final result = await Navigator.of(context).push<LivenessResult>(
      MaterialPageRoute(builder: (_) => const LivenessScreen()),
    );
    if (result == null || !mounted) return;
    setState(() => _data.liveness = result);
  }

  Future<void> _review() async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ReviewScreen(data: _data)),
    );
    if (submitted == true && mounted) setState(() => _data = KycData());
  }

  Future<void> _startOver() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard captured photos?'),
        content: const Text('The NID photos and selfie for this customer will be deleted from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
        ],
      ),
    );
    if (ok != true) return;
    await KycStorage.wipe();
    if (mounted) setState(() => _data = KycData());
  }

  @override
  Widget build(BuildContext context) {
    final nid = _data.front?.ocr?.nidNumber;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer verification'),
        actions: [
          if (_data.hasAny) TextButton(onPressed: _startOver, child: const Text('Start over')),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            const Text(
              'Capture the customer’s national ID card, then a live selfie.',
              style: TextStyle(color: AppColors.inkMuted, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 20),
            _StepTile(
              number: 1,
              title: 'NID front',
              pendingText: 'Photo side of the card',
              doneText: nid != null ? 'NID $nid' : 'Captured',
              image: _data.front?.image,
              onTap: () => _captureNid(NidSide.front),
            ),
            _StepTile(
              number: 2,
              title: 'NID back',
              pendingText: 'Reverse side of the card',
              doneText: 'Captured',
              image: _data.back?.image,
              onTap: () => _captureNid(NidSide.back),
            ),
            _StepTile(
              number: 3,
              title: 'Live selfie',
              pendingText: 'The customer follows short on-screen prompts',
              doneText: 'Liveness confirmed',
              image: _data.liveness?.selfie,
              roundThumb: true,
              onTap: _captureSelfie,
            ),
            const SizedBox(height: 12),
            const Row(
              children: [
                Icon(Icons.lock_outline, size: 16, color: AppColors.inkMuted),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Photos stay on this device until you submit.',
                    style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: FilledButton(
          onPressed: _data.isComplete ? _review : null,
          child: Text(
            _data.isComplete ? 'Review and submit' : '${_data.completedSteps} of 3 captured',
          ),
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.number,
    required this.title,
    required this.pendingText,
    required this.doneText,
    required this.image,
    required this.onTap,
    this.roundThumb = false,
  });

  final int number;
  final String title;
  final String pendingText;
  final String doneText;
  final File? image;
  final VoidCallback onTap;
  final bool roundThumb;

  @override
  Widget build(BuildContext context) {
    final done = image != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: done ? AppColors.verified.withValues(alpha: 0.4) : AppColors.line),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: done ? AppColors.verified : AppColors.paper,
                  child: done
                      ? const Icon(Icons.check, size: 18, color: Colors.white)
                      : Text('$number', style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(color: AppColors.ink, fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        done ? doneText : pendingText,
                        style: TextStyle(color: done ? AppColors.verified : AppColors.inkMuted, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (done)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(roundThumb ? 24 : 6),
                    child: Image.file(
                      image!,
                      width: roundThumb ? 48 : 64,
                      height: roundThumb ? 48 : 40,
                      fit: BoxFit.cover,
                      key: ValueKey(image!.path),
                    ),
                  )
                else
                  const Icon(Icons.photo_camera_outlined, color: AppColors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
