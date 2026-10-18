import 'dart:io';

import 'package:flutter/material.dart';

import '../core/app_config.dart';
import '../core/kyc_storage.dart';
import '../core/theme.dart';
import '../models/kyc_data.dart';
import '../services/kyc_api_service.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.data});

  final KycData data;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nid = TextEditingController(text: widget.data.front?.ocr?.nidNumber ?? '');
  late final _dob = TextEditingController(text: widget.data.front?.ocr?.dateOfBirth ?? '');
  late final _name = TextEditingController(text: widget.data.front?.ocr?.name ?? '');
  late final _bloodGroup = TextEditingController(
    text: widget.data.back?.ocr?.bloodGroup ?? 'Not detected',
  );
  final _mobile = TextEditingController();
  bool _consent = false;
  bool _submitting = false;

  @override
  void dispose() {
    _nid.dispose();
    _dob.dispose();
    _name.dispose();
    _bloodGroup.dispose();
    _mobile.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_consent) {
      _snack('Customer consent is required before submitting.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final reference = await KycApiService().submit(
        widget.data,
        fields: {
          'nid_number': _nid.text.trim(),
          'date_of_birth': _dob.text.trim(),
          'full_name': _name.text.trim(),
          'mobile': _mobile.text.trim(),
          'consent': 'true',
        },
      );
      await KycStorage.wipe();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Verification submitted'),
          content: Text(
            'Reference $reference${AppConfig.isDemo ? ' (demo mode, nothing was sent)' : ''}.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on KycApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Could not submit. Check the internet connection and try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;

    return Scaffold(
      appBar: AppBar(title: const Text('Review and submit')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              Row(
                children: [
                  Expanded(child: _Thumb(file: d.front!.image, label: 'NID front')),
                  const SizedBox(width: 10),
                  Expanded(child: _Thumb(file: d.back!.image, label: 'NID back')),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ClipOval(
                    child: Image.file(d.liveness!.selfie, width: 64, height: 64, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Live selfie: ${d.liveness!.challenges.length} prompts passed',
                      style: const TextStyle(color: AppColors.verified, fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Check these against the card. They were read automatically.',
                style: TextStyle(color: AppColors.inkMuted, fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nid,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'NID number'),
                validator: (v) => RegExp(r'^(\d{10}|\d{13}|\d{17})$').hasMatch(v?.trim() ?? '')
                    ? null
                    : 'Enter a 10, 13 or 17-digit NID number',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Name as on the card'),
                validator: (v) => (v?.trim().length ?? 0) >= 3 ? null : 'Enter the full name',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _dob,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(labelText: 'Date of birth', hintText: 'YYYY-MM-DD'),
                validator: (v) {
                  final s = v?.trim() ?? '';
                  final ok = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s) && DateTime.tryParse(s) != null;
                  return ok ? null : 'Use the format YYYY-MM-DD';
                },
              ),
              const SizedBox(height: 12),
              // Blood Group
              TextFormField(
                controller: _bloodGroup,
                decoration: const InputDecoration(labelText: 'Blood Group'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mobile,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Mobile number', hintText: '01XXXXXXXXX'),
                validator: (v) => RegExp(r'^01[3-9]\d{8}$').hasMatch(v?.trim() ?? '')
                    ? null
                    : 'Enter an 11-digit Bangladeshi mobile number',
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _consent,
                onChanged: (v) => setState(() => _consent = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'The customer agrees to the collection of their NID and photo for identity verification.',
                  style: TextStyle(fontSize: 14, color: AppColors.ink, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : const Text('Submit verification'),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.file, required this.label});

  final File file;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AspectRatio(
            aspectRatio: 85.6 / 53.98,
            child: Image.file(file, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: AppColors.inkMuted, fontSize: 13)),
      ],
    );
  }
}
