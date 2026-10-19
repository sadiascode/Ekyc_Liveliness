import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

import '../models/kyc_data.dart';

/// Reads English and Bangla text on the NID front (both smart and laminated cards print
/// the NID number, name and date of birth in English and Bangla).
class NidOcrService {
  NidOcrService()
      : _latinRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _latinRecognizer;

  /// Reads NID front with both English and Bengali OCR
  Future<NidOcrData> readFront(String path) async {
    if (kDebugMode) {
      debugPrint('=== NID OCR Started ===');
      debugPrint('Image path: $path');
    }

    // Verify Tesseract tessdata path
    try {
      final tessdataPath = await FlutterTesseractOcr.getTessdataPath();
      if (kDebugMode) {
        debugPrint('Tessdata path: $tessdataPath');
        final tessdataDir = Directory(tessdataPath);
        if (await tessdataDir.exists()) {
          final files = tessdataDir.listSync();
          debugPrint('Tessdata files: ${files.map((f) => f.path).join(", ")}');
        } else {
          debugPrint('Tessdata directory does not exist!');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to get tessdata path: $e');
      }
    }

    try {
      if (kDebugMode) {
        debugPrint('Running Google ML Kit Latin OCR...');
      }
      final latinResult =
          await _latinRecognizer.processImage(InputImage.fromFilePath(path));
      if (kDebugMode) {
        debugPrint('Latin OCR result: ${latinResult.text.length} characters');
        debugPrint('Latin OCR text: ${latinResult.text}');
      }

      String? bengaliText;

      try {
        if (kDebugMode) {
          debugPrint('Running Tesseract Bengali OCR...');
        }
        // First try to run Tesseract with both English and Bengali
        // This helps with initialization and fallback
        bengaliText = await FlutterTesseractOcr.extractText(
          path,
          language: 'ben+eng',
          args: {
            "psm": "6", // Assume a single uniform block of text
            "preserve_interword_spaces": "1",
          },
        );
        if (kDebugMode) {
          debugPrint('Bengali OCR SUCCESS');
          debugPrint(
              'Bengali OCR result length: ${bengaliText.length} characters');
          debugPrint('=== RAW BENGALI OCR TEXT START ===');
          debugPrint(bengaliText);
          debugPrint('=== RAW BENGALI OCR TEXT END ===');
        }
      } catch (e, stackTrace) {
        if (kDebugMode) {
          debugPrint('Bengali OCR failed: $e');
          debugPrint('Stack trace: $stackTrace');
        }
        // Try with just Bengali if combined fails
        try {
          if (kDebugMode) {
            debugPrint('Retrying with Bengali only...');
          }
          bengaliText = await FlutterTesseractOcr.extractText(
            path,
            language: 'ben',
            args: {
              "psm": "6",
              "preserve_interword_spaces": "1",
            },
          );
          if (kDebugMode) {
            debugPrint('Bengali-only OCR SUCCESS');
            debugPrint(
                'Bengali-only OCR result length: ${bengaliText.length} characters');
            debugPrint('=== RAW BENGALI-ONLY OCR TEXT START ===');
            debugPrint(bengaliText);
            debugPrint('=== RAW BENGALI-ONLY OCR TEXT END ===');
          }
        } catch (e2, stackTrace2) {
          if (kDebugMode) {
            debugPrint('Bengali-only OCR also failed: $e2');
            debugPrint('Stack trace: $stackTrace2');
          }
        }
      }

      return parse(latinResult.text, bengaliText: bengaliText);
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('OCR failed completely: $e');
        debugPrint('Stack trace: $stackTrace');
      }
      return const NidOcrData(rawText: '');
    }
  }

  Future<void> close() => _latinRecognizer.close();

  static NidOcrData parse(String latinText, {String? bengaliText}) {
    if (kDebugMode) {
      debugPrint('=== Parsing OCR Results ===');
      debugPrint('Latin text length: ${latinText.length}');
      debugPrint('Bengali text length: ${bengaliText?.length ?? 0}');
    }

    final lines = latinText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final upper = latinText.toUpperCase();
    final nid = _extractNid(lines);

    final englishName = _extractName(lines);
    final banglaName =
        bengaliText != null ? _extractBanglaName(bengaliText) : null;
    final banglaFatherName = bengaliText != null
        ? _extractBengaliParentName(bengaliText, 'পিতা')
        : null;
    final banglaMotherName = bengaliText != null
        ? _extractBengaliParentName(bengaliText, 'মাতা')
        : null;

    if (kDebugMode) {
      debugPrint('English name extracted: $englishName');
      debugPrint('Bangla name extracted: $banglaName');
      debugPrint('Bangla father name extracted: $banglaFatherName');
      debugPrint('Bangla mother name extracted: $banglaMotherName');
      debugPrint('[NID OCR] Final Bangla name in parse(): $banglaName');
      debugPrint(
          '[NID OCR] Final Bangla father name in parse(): $banglaFatherName');
      debugPrint(
          '[NID OCR] Final Bangla mother name in parse(): $banglaMotherName');
    }

    return NidOcrData(
      rawText: latinText,
      nidNumber: nid,
      dateOfBirth: _extractDob(latinText),
      name: englishName, // Legacy field, kept for backward compatibility
      banglaName: banglaName,
      englishName: englishName,
      banglaFatherName: banglaFatherName,
      banglaMotherName: banglaMotherName,
      bloodGroup: _extractBloodGroup(latinText),
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
    'JAN': 1,
    'FEB': 2,
    'MAR': 3,
    'APR': 4,
    'MAY': 5,
    'JUN': 6,
    'JUL': 7,
    'AUG': 8,
    'SEP': 9,
    'OCT': 10,
    'NOV': 11,
    'DEC': 12,
  };

  static String? _extractDob(String text) {
    final m = RegExp(r'(\d{1,2})\s*([A-Za-z]{3})[A-Za-z]*\s*(\d{4})')
        .firstMatch(text);
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
      if (!u.startsWith('NAME') ||
          u.contains('FATHER') ||
          u.contains('MOTHER')) {
        continue;
      }
      final colon = lines[i].indexOf(':');
      final inline = colon >= 0 ? lines[i].substring(colon + 1).trim() : '';
      if (inline.length > 2) return inline;
      if (i + 1 < lines.length) return lines[i + 1];
    }
    return null;
  }

  static String? _extractBanglaName(String bengaliText) {
    if (kDebugMode) {
      debugPrint('=== Extracting Bangla Name ===');
      debugPrint('Input text length: ${bengaliText.length}');
    }

    // If bengaliText is empty or null, return null immediately
    if (bengaliText.trim().isEmpty) {
      if (kDebugMode) {
        debugPrint('Bengali text is empty, returning null');
      }
      return null;
    }

    final lines = bengaliText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (kDebugMode) {
      debugPrint('Total lines after split: ${lines.length}');
      for (var i = 0; i < lines.length; i++) {
        debugPrint('Line $i: "${lines[i]}" (length: ${lines[i].length})');
      }
    }

    // Bengali Unicode ranges
    // Letters: U+0980 to U+09DF (অ to য়)
    // Vowel signs (kars): U+09BE to U+09D7 (া to ৗ)
    // Signs and modifiers: U+09D8 to U+09DF (৘ to য়)
    // Digits: U+09E6 to U+09EF (০ to ৯)
    final bengaliLetterWithSignsRegex =
        RegExp(r'[\u0980-\u09DF]+'); // Letters + vowel signs + modifiers
    final bengaliDigitRegex = RegExp(r'[\u09E6-\u09EF]'); // Bengali digits ০-৯
    final englishDigitRegex = RegExp(r'[0-9]');
    final latinLetterRegex = RegExp(r'[a-zA-Z]');

    // Helper function to validate a name candidate
    bool isValidName(String text) {
      if (text.trim().isEmpty) return false;

      // Remove all Bengali letters (with signs) and spaces, check if anything remains
      final nonBengaliContent =
          text.replaceAll(RegExp(r'[\u0980-\u09DF\s]'), '');
      if (nonBengaliContent.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
              '  Invalid: contains non-Bengali content: "$nonBengaliContent"');
        }
        return false;
      }

      // Check for Bengali digits
      if (bengaliDigitRegex.hasMatch(text)) {
        if (kDebugMode) {
          debugPrint('  Invalid: contains Bengali digits');
        }
        return false;
      }

      // Check for English digits
      if (englishDigitRegex.hasMatch(text)) {
        if (kDebugMode) {
          debugPrint('  Invalid: contains English digits');
        }
        return false;
      }

      // Check for Latin letters
      if (latinLetterRegex.hasMatch(text)) {
        if (kDebugMode) {
          debugPrint('  Invalid: contains Latin letters');
        }
        return false;
      }

      // Count Bengali characters (including vowel signs)
      final letterMatches = bengaliLetterWithSignsRegex.allMatches(text);
      final letterCount =
          letterMatches.fold(0, (sum, m) => sum + m.group(0)!.length);

      // Require at least 2 Bengali characters
      if (letterCount < 2) {
        if (kDebugMode) {
          debugPrint(
              '  Invalid: insufficient Bengali characters ($letterCount)');
        }
        return false;
      }

      if (kDebugMode) {
        debugPrint('  Valid: $letterCount Bengali characters');
      }
      return true;
    }

    // Helper function to clean and normalize a name
    String cleanName(String text) {
      // Remove all non-Bengali characters (letters + signs) and spaces
      var cleaned = text.replaceAll(RegExp(r'[^\u0980-\u09DF\s]'), '').trim();
      // Normalize multiple spaces to single space
      cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
      return cleaned;
    }

    // Strategy 1: Look for "নাম" (name) label and extract nearby text
    if (kDebugMode) {
      debugPrint('Strategy 1: Looking for "নাম" label');
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Check if line contains "নাম" (name) or "নামঃ" (Bangla naam)
      if (line.contains('নাম')) {
        if (kDebugMode) {
          debugPrint('Found "নাম" at line $i: "$line"');
        }

        // Try multiple extraction methods
        List<String> candidates = [];

        // Method 1: Extract after colon (:)
        final colonIndex = line.indexOf(':');
        if (colonIndex >= 0 && colonIndex + 1 < line.length) {
          final afterColon = line.substring(colonIndex + 1).trim();
          if (afterColon.isNotEmpty) {
            candidates.add(afterColon);
            if (kDebugMode) {
              debugPrint('  Candidate after colon: "$afterColon"');
            }
          }
        }

        // Method 2: Extract after Bengali colon (ঃ)
        final bengaliColonIndex = line.indexOf('ঃ');
        if (bengaliColonIndex >= 0 && bengaliColonIndex + 1 < line.length) {
          final afterBengaliColon =
              line.substring(bengaliColonIndex + 1).trim();
          if (afterBengaliColon.isNotEmpty) {
            candidates.add(afterBengaliColon);
            if (kDebugMode) {
              debugPrint('  Candidate after ঃ: "$afterBengaliColon"');
            }
          }
        }

        // Method 3: Extract after "নাম" (assuming space or no separator)
        final naamIndex = line.indexOf('নাম');
        if (naamIndex >= 0 && naamIndex + 3 < line.length) {
          final afterNaam = line.substring(naamIndex + 3).trim();
          if (afterNaam.isNotEmpty) {
            candidates.add(afterNaam);
            if (kDebugMode) {
              debugPrint('  Candidate after নাম: "$afterNaam"');
            }
          }
        }

        // Method 4: Use next line if current line only has label
        if (i + 1 < lines.length) {
          final nextLine = lines[i + 1].trim();
          if (nextLine.isNotEmpty) {
            candidates.add(nextLine);
            if (kDebugMode) {
              debugPrint('  Candidate from next line: "$nextLine"');
            }
          }
        }

        // Validate and clean candidates
        for (final candidate in candidates) {
          final cleaned = cleanName(candidate);
          if (kDebugMode) {
            debugPrint(
                '  Validating candidate: "$candidate" -> cleaned: "$cleaned"');
          }

          if (isValidName(cleaned)) {
            if (kDebugMode) {
              debugPrint('✓ Valid name found from label: "$cleaned"');
              debugPrint('[NID OCR] Extracted Bangla name: $cleaned');
            }
            return cleaned;
          }
        }

        if (kDebugMode) {
          debugPrint('Label found but no valid name extracted');
        }
      }
    }

    // Strategy 2: Position-based fallback - look for lines that appear to be names
    // Names typically: moderate length, only Bengali letters, no digits
    if (kDebugMode) {
      debugPrint('Strategy 2: Position-based fallback');
    }

    // Skip lines that are clearly labels
    final labelPatterns = [
      RegExp(r'^[\u09A8\u09BE\u09AE]+$'), // নাম alone
      RegExp(r'^[\u09A8\u09BE\u09AE][:\s]'), // নাম with colon/space
      RegExp(r'[\u09AA\u09BE\u09A4\u09A4\u09C7\u09A6]'), // পাত্তাদেদ
      RegExp(r'[\u0986\u0987\u09A1\u09BF]'), // আইডি
      RegExp(r'[\u099C\u09A8\u09CD\u09AE]'), // জন্ম
      RegExp(r'[\u09A4\u09BE\u09B0\u09BF\u0996]'), // তারিখ
      RegExp(r'[\u09B0\u0995\u09CD\u09A4]'), // রক্ত
      RegExp(r'[\u0997\u09CD\u09B0\u09C1\u09AA]'), // গ্রুপ
      RegExp(r'[\u09B8\u09CD\u09AC\u09BE\u0995\u09CD\u09B7\u09BE]'), // স্বাক্ষর
    ];

    List<String> validCandidates = [];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Skip if no Bengali letters at all
      if (!bengaliLetterWithSignsRegex.hasMatch(line)) {
        if (kDebugMode) {
          debugPrint('Line $i: Skipped (no Bengali letters)');
        }
        continue;
      }

      // Skip label lines
      bool isLabel = false;
      for (final pattern in labelPatterns) {
        if (pattern.hasMatch(line)) {
          isLabel = true;
          if (kDebugMode) {
            debugPrint('Line $i: Skipped (label pattern)');
          }
          break;
        }
      }

      if (isLabel) continue;

      // Skip lines with digits (Bengali or English)
      if (bengaliDigitRegex.hasMatch(line) ||
          englishDigitRegex.hasMatch(line)) {
        if (kDebugMode) {
          debugPrint('Line $i: Skipped (contains digits)');
        }
        continue;
      }

      // Skip lines with Latin letters
      if (latinLetterRegex.hasMatch(line)) {
        if (kDebugMode) {
          debugPrint('Line $i: Skipped (contains Latin letters)');
        }
        continue;
      }

      // Clean and validate
      final cleaned = cleanName(line);
      if (isValidName(cleaned)) {
        validCandidates.add(cleaned);
        if (kDebugMode) {
          debugPrint('Line $i: Valid candidate: "$cleaned"');
        }
      } else {
        if (kDebugMode) {
          debugPrint('Line $i: Invalid after validation');
        }
      }
    }

    if (kDebugMode) {
      debugPrint(
          'Total valid candidates from fallback: ${validCandidates.length}');
    }

    // If we have valid candidates, prefer the longest one (names are typically longer than random text)
    if (validCandidates.isNotEmpty) {
      validCandidates.sort((a, b) => b.length.compareTo(a.length));
      final bestCandidate = validCandidates.first;

      if (kDebugMode) {
        debugPrint(
            '✓ Selected best candidate from fallback: "$bestCandidate" (length: ${bestCandidate.length})');
      }
      if (kDebugMode) {
        debugPrint('[NID OCR] Extracted Bangla name: $bestCandidate');
      }
      return bestCandidate;
    }

    // No valid name found
    if (kDebugMode) {
      debugPrint('✗ No valid Bangla name found in OCR output');
      debugPrint('[NID OCR] Extracted Bangla name: null');
    }
    return null;
  }

  static String? _extractBengaliParentName(String bengaliText, String label) {
    if (kDebugMode) {
      debugPrint('=== Extracting Bangla Parent Name ===');
      debugPrint('Label: $label');
      debugPrint('Input text length: ${bengaliText.length}');
    }

    if (bengaliText.trim().isEmpty) {
      if (kDebugMode) {
        debugPrint('Bengali text is empty, returning null');
      }
      return null;
    }

    final lines = bengaliText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (kDebugMode) {
      debugPrint('Total lines after split: ${lines.length}');
      for (var i = 0; i < lines.length; i++) {
        debugPrint('Line $i: "${lines[i]}" (length: ${lines[i].length})');
      }
    }

    // Bengali Unicode ranges including vowel signs
    final bengaliLetterWithSignsRegex = RegExp(r'[\u0980-\u09DF]+');
    final bengaliDigitRegex = RegExp(r'[\u09E6-\u09EF]');
    final englishDigitRegex = RegExp(r'[0-9]');
    final latinLetterRegex = RegExp(r'[a-zA-Z]');

    // Helper function to validate a name candidate
    bool isValidName(String text) {
      if (text.trim().isEmpty) return false;

      final nonBengaliContent =
          text.replaceAll(RegExp(r'[\u0980-\u09DF\s]'), '');
      if (nonBengaliContent.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
              '  Invalid: contains non-Bengali content: "$nonBengaliContent"');
        }
        return false;
      }

      if (bengaliDigitRegex.hasMatch(text)) {
        if (kDebugMode) {
          debugPrint('  Invalid: contains Bengali digits');
        }
        return false;
      }

      if (englishDigitRegex.hasMatch(text)) {
        if (kDebugMode) {
          debugPrint('  Invalid: contains English digits');
        }
        return false;
      }

      if (latinLetterRegex.hasMatch(text)) {
        if (kDebugMode) {
          debugPrint('  Invalid: contains Latin letters');
        }
        return false;
      }

      final letterMatches = bengaliLetterWithSignsRegex.allMatches(text);
      final letterCount =
          letterMatches.fold(0, (sum, m) => sum + m.group(0)!.length);

      if (letterCount < 2) {
        if (kDebugMode) {
          debugPrint(
              '  Invalid: insufficient Bengali characters ($letterCount)');
        }
        return false;
      }

      if (kDebugMode) {
        debugPrint('  Valid: $letterCount Bengali characters');
      }
      return true;
    }

    // Helper function to clean and normalize a name
    String cleanName(String text) {
      var cleaned = text.replaceAll(RegExp(r'[^\u0980-\u09DF\s]'), '').trim();
      cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
      return cleaned;
    }

    // Look for the label and extract nearby text
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line.contains(label)) {
        if (kDebugMode) {
          debugPrint('Found "$label" at line $i: "$line"');
        }

        List<String> candidates = [];

        // Method 1: Extract after colon (:)
        final colonIndex = line.indexOf(':');
        if (colonIndex >= 0 && colonIndex + 1 < line.length) {
          final afterColon = line.substring(colonIndex + 1).trim();
          if (afterColon.isNotEmpty) {
            candidates.add(afterColon);
            if (kDebugMode) {
              debugPrint('  Candidate after colon: "$afterColon"');
            }
          }
        }

        // Method 2: Extract after Bengali colon (ঃ)
        final bengaliColonIndex = line.indexOf('ঃ');
        if (bengaliColonIndex >= 0 && bengaliColonIndex + 1 < line.length) {
          final afterBengaliColon =
              line.substring(bengaliColonIndex + 1).trim();
          if (afterBengaliColon.isNotEmpty) {
            candidates.add(afterBengaliColon);
            if (kDebugMode) {
              debugPrint('  Candidate after ঃ: "$afterBengaliColon"');
            }
          }
        }

        // Method 3: Extract after label (assuming space or no separator)
        final labelIndex = line.indexOf(label);
        if (labelIndex >= 0 && labelIndex + label.length < line.length) {
          final afterLabel = line.substring(labelIndex + label.length).trim();
          if (afterLabel.isNotEmpty) {
            candidates.add(afterLabel);
            if (kDebugMode) {
              debugPrint('  Candidate after $label: "$afterLabel"');
            }
          }
        }

        // Method 4: Use next line if current line only has label
        if (i + 1 < lines.length) {
          final nextLine = lines[i + 1].trim();
          if (nextLine.isNotEmpty) {
            candidates.add(nextLine);
            if (kDebugMode) {
              debugPrint('  Candidate from next line: "$nextLine"');
            }
          }
        }

        // Validate and clean candidates
        for (final candidate in candidates) {
          final cleaned = cleanName(candidate);
          if (kDebugMode) {
            debugPrint(
                '  Validating candidate: "$candidate" -> cleaned: "$cleaned"');
          }

          if (isValidName(cleaned)) {
            if (kDebugMode) {
              debugPrint('✓ Valid $label name found: "$cleaned"');
              debugPrint('[NID OCR] Extracted Bangla $label name: $cleaned');
            }
            return cleaned;
          }
        }

        if (kDebugMode) {
          debugPrint('Label found but no valid name extracted');
        }
      }
    }

    if (kDebugMode) {
      debugPrint('✗ No valid Bangla $label name found in OCR output');
      debugPrint('[NID OCR] Extracted Bangla $label name: null');
    }
    return null;
  }

  static String? _extractBloodGroup(String text) {
    final upper = text.toUpperCase();
    // Match variations: B+, B +, B+, B POSITIVE, B+POSITIVE, B+, etc.
    // Handle various spacing, punctuation, and label formats
    final pattern = RegExp(
        r'(?:BLOOD\s*GROUP\s*[:\s]*)?(A[\s\+\-]+|B[\s\+\-]+|AB[\s\+\-]+|O[\s\+\-]+|A\s*POSITIVE|A\s*NEGATIVE|B\s*POSITIVE|B\s*NEGATIVE|AB\s*POSITIVE|AB\s*NEGATIVE|O\s*POSITIVE|O\s*NEGATIVE)');
    final match = pattern.firstMatch(upper);

    if (kDebugMode && match != null) {
      debugPrint('Blood group matched: ${match.group(0)}');
    }

    if (match != null) {
      var bg = match.group(0)!.trim();
      // Remove "BLOOD GROUP" prefix if present
      bg = bg.replaceAll(RegExp(r'BLOOD\s*GROUP\s*[:\s]*'), '');
      // Normalize spacing and remove all whitespace
      bg = bg.replaceAll(RegExp(r'\s+'), '');
      // Convert POSITIVE/NEGATIVE to +/-
      if (bg.contains('POSITIVE')) {
        bg = bg.replaceAll('POSITIVE', '+');
      } else if (bg.contains('NEGATIVE')) {
        bg = bg.replaceAll('NEGATIVE', '-');
      }
      if (kDebugMode) {
        debugPrint('Blood group extracted: $bg');
      }
      return bg;
    }

    if (kDebugMode) {
      debugPrint('Blood group not found in OCR text');
    }
    return null;
  }
}
