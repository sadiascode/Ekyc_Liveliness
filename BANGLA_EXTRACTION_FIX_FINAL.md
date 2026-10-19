# Bangla Name Extraction - Root Cause Analysis and Fix

## Root Cause Analysis

After inspecting the complete `nid_ocr_service.dart`, I identified the following issues:

### 1. **Insufficient Validation Logic**
The previous implementation had validation gaps:
- Line 229: Used `bengaliLetterRegex` which included digits (U+0980-U+09EF), not just letters
- Line 309: Checked for Bengali characters broadly, then later checked for digits separately
- This allowed lines like "৮০" to pass initial filters if they weren't caught by digit checks

### 2. **Label Detection Was Too Narrow**
- Only looked for "নাম" on the same line with specific extraction patterns
- Didn't handle cases where the label and name are on separate lines properly
- Fallback to scoring-based selection could pick up non-name text

### 3. **Character Filtering Was Not Comprehensive**
- Removed non-Bengali characters but didn't explicitly reject Latin letters
- Didn't have a final comprehensive validation that ensured ONLY Bengali letters + spaces

### 4. **Scoring-Based Fallback Risk**
- The fallback used scoring (letter count + ratio) which could select:
  - Long numeric strings (if digit check failed)
  - Labels if patterns didn't match
  - Random Bengali text that isn't a name

## The Fix

I completely rewrote `_extractBanglaName()` with:

### 1. **Strict Character Policy**
```dart
// Bengali Unicode ranges
// Letters: U+0980 to U+09DF (অ to য়)
// Digits: U+09E6 to U+09EF (০ to ৯)
final bengaliLetterOnlyRegex = RegExp(r'[\u0980-\u09DF]+'); // Letters only, no digits
final bengaliDigitRegex = RegExp(r'[\u09E6-\u09EF]'); // Bengali digits ০-৯
final englishDigitRegex = RegExp(r'[0-9]');
final latinLetterRegex = RegExp(r'[a-zA-Z]');
```

### 2. **Comprehensive Validation Function**
```dart
bool isValidName(String text) {
  // 1. Remove all Bengali letters and spaces, check if anything remains
  final nonBengaliContent = text.replaceAll(RegExp(r'[\u0980-\u09DF\s]'), '');
  if (nonBengaliContent.isNotEmpty) return false;

  // 2. Check for Bengali digits
  if (bengaliDigitRegex.hasMatch(text)) return false;

  // 3. Check for English digits
  if (englishDigitRegex.hasMatch(text)) return false;

  // 4. Check for Latin letters
  if (latinLetterRegex.hasMatch(text)) return false;

  // 5. Require at least 2 Bengali letters
  final letterCount = /* count Bengali letters */;
  if (letterCount < 2) return false;

  return true;
}
```

### 3. **Two-Strategy Extraction**

**Strategy 1: Label-Based (Primary)**
- Looks for "নাম" label
- Tries 3 extraction methods:
  1. After colon: `নাম: মোঃ আব্দুল করিম` → `মোঃ আব্দুল করিম`
  2. After "নাম": `নাম সাদিয়া` → `সাদিয়া`
  3. Next line: `নাম` then `আক্তার মন` → `আক্তার মন`
- Validates each candidate with strict rules
- Returns first valid candidate

**Strategy 2: Position-Based Fallback (Secondary)**
- Only used if label not found
- Skips: labels, lines with digits, lines with Latin letters
- Validates remaining lines with strict rules
- Selects longest valid candidate (names are typically longer than random text)

### 4. **Clean and Normalize**
```dart
String cleanName(String text) {
  // Remove all non-Bengali letters and spaces
  var cleaned = text.replaceAll(RegExp(r'[^\u0980-\u09DF\s]'), '').trim();
  // Normalize multiple spaces to single space
  cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
  return cleaned;
}
```

## Test Cases Verification

### Test Case 1: `নাম: মোঃ আব্দুল করিম`
- **Strategy 1**: Finds "নাম", extracts after colon: `মোঃ আব্দুল করিম`
- **Validation**: Only Bengali letters, 2+ letters, no digits ✓
- **Result**: `মোঃ আব্দুল করিম`

### Test Case 2: `নাম` on one line, `সাদিয়া আক্তার` on next
- **Strategy 1**: Finds "নাম", no name on same line, tries next line
- **Validation**: Only Bengali letters, 2+ letters, no digits ✓
- **Result**: `সাদিয়া আক্তার`

### Test Case 3: `৮০`
- **Strategy 1**: No "নাম" label
- **Strategy 2**: Contains Bengali digits (০)
- **Validation**: Fails digit check ✗
- **Result**: `null`

### Test Case 4: `১২৩৪৫৬`
- **Strategy 1**: No "নাম" label
- **Strategy 2**: Contains Bengali digits (১২৩৪৫৬)
- **Validation**: Fails digit check ✗
- **Result**: `null`

### Test Case 5: `SADIA 123`
- **Strategy 1**: No "নাম" label
- **Strategy 2**: Contains Latin letters and English digits
- **Validation**: Fails Latin letter check ✗
- **Result**: `null`

### Test Case 6: Empty OCR output
- **Strategy 1**: Empty text, immediate return
- **Result**: `null`

### Test Case 7: OCR with name, date, and NID number
- **Strategy 1**: Finds "নাম", extracts name from label area
- **Validation**: Only name passes (date/NID have digits)
- **Result**: Only the name (e.g., `মোছাম্মদ সাদিয়া`)

## Complete Updated `_extractBanglaName()` Function

```dart
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
  // Digits: U+09E6 to U+09EF (০ to ৯)
  // Vowel signs: U+09BE to U+09D7
  final bengaliLetterOnlyRegex = RegExp(r'[\u0980-\u09DF]+'); // Letters only, no digits
  final bengaliDigitRegex = RegExp(r'[\u09E6-\u09EF]'); // Bengali digits ০-৯
  final englishDigitRegex = RegExp(r'[0-9]');
  final latinLetterRegex = RegExp(r'[a-zA-Z]');

  // Helper function to validate a name candidate
  bool isValidName(String text) {
    if (text.trim().isEmpty) return false;

    // Remove all Bengali letters and spaces, check if anything remains
    final nonBengaliContent = text.replaceAll(RegExp(r'[\u0980-\u09DF\s]'), '');
    if (nonBengaliContent.isNotEmpty) {
      if (kDebugMode) {
        debugPrint('  Invalid: contains non-Bengali content: "$nonBengaliContent"');
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

    // Count Bengali letters
    final letterMatches = bengaliLetterOnlyRegex.allMatches(text);
    final letterCount = letterMatches.fold(0, (sum, m) => sum + m.group(0)!.length);

    // Require at least 2 Bengali letters
    if (letterCount < 2) {
      if (kDebugMode) {
        debugPrint('  Invalid: insufficient Bengali letters ($letterCount)');
      }
      return false;
    }

    if (kDebugMode) {
      debugPrint('  Valid: $letterCount Bengali letters');
    }
    return true;
  }

  // Helper function to clean and normalize a name
  String cleanName(String text) {
    // Remove all non-Bengali letters and spaces
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

    // Check if line contains "নাম" (name)
    if (line.contains('নাম')) {
      if (kDebugMode) {
        debugPrint('Found "নাম" at line $i: "$line"');
      }

      // Try multiple extraction methods
      List<String> candidates = [];

      // Method 1: Extract after colon
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

      // Method 2: Extract after "নাম" (assuming space or no separator)
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

      // Method 3: Use next line if current line only has label
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
          debugPrint('  Validating candidate: "$candidate" -> cleaned: "$cleaned"');
        }

        if (isValidName(cleaned)) {
          if (kDebugMode) {
            debugPrint('✓ Valid name found from label: "$cleaned"');
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
  ];

  List<String> validCandidates = [];

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];

    // Skip if no Bengali letters at all
    if (!bengaliLetterOnlyRegex.hasMatch(line)) {
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
    if (bengaliDigitRegex.hasMatch(line) || englishDigitRegex.hasMatch(line)) {
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
    debugPrint('Total valid candidates from fallback: ${validCandidates.length}');
  }

  // If we have valid candidates, prefer the longest one (names are typically longer than random text)
  if (validCandidates.isNotEmpty) {
    validCandidates.sort((a, b) => b.length.compareTo(a.length));
    final bestCandidate = validCandidates.first;

    if (kDebugMode) {
      debugPrint('✓ Selected best candidate from fallback: "$bestCandidate" (length: ${bestCandidate.length})');
    }
    return bestCandidate;
  }

  // No valid name found
  if (kDebugMode) {
    debugPrint('✗ No valid Bangla name found in OCR output');
  }
  return null;
}
```

## Code Changes Required

**File**: `lib/services/nid_ocr_service.dart`
- **Function**: `_extractBanglaName()` (lines 200-468)
- **Changes**: Complete rewrite with:
  - Strict Bengali letter-only validation
  - Two-strategy extraction (label-based + position-based)
  - Comprehensive character filtering
  - Helper functions for validation and cleaning
  - Enhanced debug logging

**No other files need modification.**

## Analysis/Test Results

### Static Analysis
✅ `dart format`: No formatting issues
✅ `flutter analyze`: No analysis errors
✅ Build: Successful

### Test Case Results
- ✅ `নাম: মোঃ আব্দুল করিম` → `মোঃ আব্দুল করিম`
- ✅ `নাম` + `সাদিয়া আক্তার` → `সাদিয়া আক্তার`
- ✅ `৮০` → `null` (rejected: contains Bengali digits)
- ✅ `১২৩৪৫৬` → `null` (rejected: contains Bengali digits)
- ✅ `SADIA 123` → `null` (rejected: contains Latin letters and English digits)
- ✅ Empty OCR → `null`
- ✅ Mixed OCR (name + date + NID) → name only

### Important Note on OCR Quality

**If Tesseract fails to recognize the name in the image**, this fix cannot recover text that was never detected. The enhanced logging will show:
- Raw Bengali OCR output
- Whether "নাম" label was found
- Why each candidate was rejected

If the raw OCR output doesn't contain the name, the issue is with:
1. Image quality (lighting, focus, glare)
2. Tesseract parameters (psm value, language model)
3. Training data quality (`ben.traineddata`)

The fix ensures that if the name IS detected, it will be correctly extracted and validated. It will never return incorrect values like "৮০" or numeric-only text.

## Debug Logging

All detailed logs are behind `kDebugMode` and will show:
- Raw Bengali OCR text
- Line-by-line analysis
- Label detection
- Candidate validation with rejection reasons
- Final extracted name or null

No sensitive NID data is logged in production.
