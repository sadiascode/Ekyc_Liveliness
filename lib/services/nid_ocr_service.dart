import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/kyc_data.dart';

/// Reads English text on the NID front (both smart and laminated cards print
/// the NID number, name and date of birth in English).
class NidOcrService {
  NidOcrService() : _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;

  Future<NidOcrData> readFront(String path) async {
    try {
      final result = await _recognizer.processImage(InputImage.fromFilePath(path));
      return parse(result.text);
    } catch (_) {
      return const NidOcrData(rawText: '');
    }
  }

  Future<void> close() => _recognizer.close();

  static NidOcrData parse(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final upper = text.toUpperCase();
    final nid = _extractNid(lines);

    return NidOcrData(
      rawText: text,
      nidNumber: nid,
      dateOfBirth: _extractDob(text),
      name: _extractName(lines),
      looksLikeNidFront: nid != null ||
          upper.contains('NATIONAL ID') ||
          upper.contains('ID NO'),
    );
  }

  static String? _extractNid(List<String> lines) {
    final pattern = RegExp(r'(?<!\d)(\d{17}|\d{13}|\d{10})(?!\d)');
    String? fallback;
    for (final line in lines) {
      final compact = line.replaceAll(RegExp(r'(?<=\d)[\s-]+(?=\d)'), '');
      final m = pattern.firstMatch(compact);
      if (m == null) continue;
      final u = line.toUpperCase();
      if (u.contains('ID NO') || u.contains('NID')) return m.group(1);
      fallback ??= m.group(1);
    }
    return fallback;
  }

  static const _months = {
    'JAN': 1, 'FEB': 2, 'MAR': 3, 'APR': 4, 'MAY': 5, 'JUN': 6,
    'JUL': 7, 'AUG': 8, 'SEP': 9, 'OCT': 10, 'NOV': 11, 'DEC': 12,
  };

  static String? _extractDob(String text) {
    final m = RegExp(r'(\d{1,2})\s*([A-Za-z]{3})[A-Za-z]*\s*(\d{4})').firstMatch(text);
    if (m == null) return null;
    final month = _months[m.group(2)!.toUpperCase()];
    if (month == null) return null;
    final day = int.parse(m.group(1)!);
    final year = int.parse(m.group(3)!);
    if (day < 1 || day > 31 || year < 1900) return null;
    return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  }

  static String? _extractName(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      final u = lines[i].toUpperCase();
      if (!u.startsWith('NAME') || u.contains('FATHER') || u.contains('MOTHER')) {
        continue;
      }
      final colon = lines[i].indexOf(':');
      final inline = colon >= 0 ? lines[i].substring(colon + 1).trim() : '';
      if (inline.length > 2) return inline;
      if (i + 1 < lines.length) return lines[i + 1];
    }
    return null;
  }
}
