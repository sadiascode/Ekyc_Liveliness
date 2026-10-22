import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

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
  late final _nid =
      TextEditingController(text: widget.data.front?.ocr?.nidNumber ?? '');
  late final _dob =
      TextEditingController(text: widget.data.front?.ocr?.dateOfBirth ?? '');
  late final _banglaName =
      TextEditingController(text: widget.data.front?.ocr?.banglaName ?? '');
  late final _englishName =
      TextEditingController(text: widget.data.front?.ocr?.englishName ?? '');
  late final _banglaFatherName = TextEditingController(
      text: widget.data.front?.ocr?.banglaFatherName ?? '');
  late final _banglaMotherName = TextEditingController(
      text: widget.data.front?.ocr?.banglaMotherName ?? '');
  late final _address =
      TextEditingController(text: widget.data.back?.ocr?.address ?? '');
  late final _postOffice =
      TextEditingController(text: widget.data.back?.ocr?.postOffice ?? '');
  late final _bloodGroup = TextEditingController(
    text: widget.data.back?.ocr?.bloodGroup ?? 'Not detected',
  );
  final _mobile = TextEditingController();
  bool _consent = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint('=== ReviewScreen Init ===');
      debugPrint('Front OCR data: ${widget.data.front?.ocr}');
      debugPrint('Back OCR data: ${widget.data.back?.ocr}');
      debugPrint('Bangla name from OCR: ${widget.data.front?.ocr?.banglaName}');
      debugPrint(
          'English name from OCR: ${widget.data.front?.ocr?.englishName}');
      debugPrint(
          'Bangla father name from OCR: ${widget.data.front?.ocr?.banglaFatherName}');
      debugPrint('Address from OCR: ${widget.data.back?.ocr?.address}');
      debugPrint('Post office from OCR: ${widget.data.back?.ocr?.postOffice}');
      debugPrint('NID number from OCR: ${widget.data.front?.ocr?.nidNumber}');
      debugPrint('Bangla Name controller initial value: "${_banglaName.text}"');
      debugPrint(
          'English Name controller initial value: "${_englishName.text}"');
      debugPrint(
          'Bangla Father Name controller initial value: "${_banglaFatherName.text}"');
      debugPrint('Address controller initial value: "${_address.text}"');
      debugPrint('Post office controller initial value: "${_postOffice.text}"');
    }
  }

  @override
  void dispose() {
    _nid.dispose();
    _dob.dispose();
    _banglaName.dispose();
    _englishName.dispose();
    _banglaFatherName.dispose();
    _address.dispose();
    _postOffice.dispose();
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
      final fields = {
        'nid_number': _nid.text.trim(),
        'date_of_birth': _dob.text.trim(),
        'full_name': _englishName.text.trim(),
        'mobile': _mobile.text.trim(),
        'consent': 'true',
      };

      // Include Bangla name if available and not empty
      if (_banglaName.text.trim().isNotEmpty) {
        fields['bangla_name'] = _banglaName.text.trim();
      }

      // Include Bangla father name if available and not empty
      if (_banglaFatherName.text.trim().isNotEmpty) {
        fields['bangla_father_name'] = _banglaFatherName.text.trim();
      }

      // Include address if available and not empty
      if (_address.text.trim().isNotEmpty) {
        fields['address'] = _address.text.trim();
      }

      // Include post office if available and not empty
      if (_postOffice.text.trim().isNotEmpty) {
        fields['post_office'] = _postOffice.text.trim();
      }

      final reference = await KycApiService().submit(
        widget.data,
        fields: fields,
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
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done')),
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
                  Expanded(
                      child: _Thumb(file: d.front!.image, label: 'NID front')),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _Thumb(file: d.back!.image, label: 'NID back')),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ClipOval(
                    child: Image.file(d.liveness!.selfie,
                        width: 64, height: 64, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Live selfie: ${d.liveness!.challenges.length} prompts passed',
                      style: const TextStyle(
                          color: AppColors.verified,
                          fontSize: 15,
                          fontWeight: FontWeight.w500),
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
                validator: (v) => RegExp(r'^(\d{10}|\d{13}|\d{17})$')
                        .hasMatch(v?.trim() ?? '')
                    ? null
                    : 'Enter a 10, 13 or 17-digit NID number',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _banglaName,
                decoration: const InputDecoration(labelText: 'Bangla Name'),
                validator: (v) => (v?.trim().length ?? 0) >= 3
                    ? null
                    : 'Enter the Bangla name',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _englishName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'English Name'),
                validator: (v) => (v?.trim().length ?? 0) >= 3
                    ? null
                    : 'Enter the English name',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _banglaFatherName,
                decoration: const InputDecoration(labelText: 'Father Name'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _banglaMotherName,
                decoration: const InputDecoration(labelText: 'Mother Name'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _postOffice,
                decoration: const InputDecoration(labelText: 'Post Office'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _dob,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(
                    labelText: 'Date of birth', hintText: 'YYYY-MM-DD'),
                validator: (v) {
                  final s = v?.trim() ?? '';
                  final ok = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s) &&
                      DateTime.tryParse(s) != null;
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
                decoration: const InputDecoration(
                    labelText: 'Mobile number', hintText: '01XXXXXXXXX'),
                validator: (v) =>
                    RegExp(r'^01[3-9]\d{8}$').hasMatch(v?.trim() ?? '')
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
                  style: TextStyle(
                      fontSize: 14, color: AppColors.ink, height: 1.35),
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
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
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
        Text(label,
            style: const TextStyle(color: AppColors.inkMuted, fontSize: 13)),
      ],
    );
  }
}
