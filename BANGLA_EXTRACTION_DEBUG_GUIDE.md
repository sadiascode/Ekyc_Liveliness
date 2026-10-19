# Bangla Name Extraction Debug Guide

## Current Status

The app successfully builds and English OCR works (detecting "MST. SADIA AKTER MON" and NID number "5117448281"), but Bangla name extraction returns `null`.

## Enhanced Debug Logging Added

I've added comprehensive debug logging to help diagnose the issue:

### 1. Raw Bengali OCR Text
The logs now show the complete raw output from Tesseract:
```
=== RAW BENGALI OCR TEXT START ===
[Complete Bengali OCR output]
=== RAW BENGALI OCR TEXT END ===
```

### 2. Line-by-Line Analysis
Each line is analyzed with details:
```
Line 0: "text" (length: X)
Line 1: "text" (length: Y)
...
```

### 3. Candidate Scoring
All potential name candidates are ranked by score:
```
Total candidates found: N
Candidates ranked by score:
  Rank 0: "name" (score: XXX)
  Rank 1: "name" (score: YYY)
...
```

### 4. Final Selection
The final extracted name is logged:
```
Final Bangla name: "extracted_name"
```

## Testing Instructions

### Step 1: Run the App with Debug Mode
```bash
flutter run
```

### Step 2: Capture NID Front
1. Navigate to NID capture screen
2. Capture the front of the Bangladesh NID card
3. Wait for OCR processing

### Step 3: Inspect Debug Logs
Look for the following sections in the terminal output:

#### Section 1: Bengali OCR Output
```
Running Tesseract Bengali OCR...
Bengali OCR SUCCESS
Bengali OCR result length: X characters
=== RAW BENGALI OCR TEXT START ===
[This is the critical part - copy this entire section]
=== RAW BENGALI OCR TEXT END ===
```

#### Section 2: Extraction Process
```
=== Extracting Bangla Name ===
Input text length: X
Total lines after split: N
Line 0: "text" (length: X)
Line 1: "text" (length: Y)
...
```

#### Section 3: Candidate Analysis
```
Line X: Candidate - Original: "line", Cleaned: "name", Bengali chars: N, Ratio: R, Score: S
Total candidates found: N
Candidates ranked by score:
  Rank 0: "name" (score: S)
...
Final Bangla name: "name"
```

## What to Look For

### If Bengali OCR Returns Empty
```
Bengali OCR result length: 0 characters
```
**Cause**: Tesseract not detecting Bengali text
**Solution**:
- Check if the NID actually has Bengali text
- Verify image quality (lighting, focus, glare)
- Try different Tesseract parameters (psm values)

### If Bengali OCR Has Text But No Candidates
```
Total candidates found: 0
```
**Cause**: All lines filtered out by label patterns or length checks
**Solution**:
- Check the line-by-line analysis to see which lines were skipped
- The issue might be label patterns matching actual names
- Length threshold might be too strict

### If Candidates Exist But Wrong One Selected
```
Candidates ranked by score:
  Rank 0: "wrong_name" (score: XXX)
  Rank 1: "correct_name" (score: YYY)
```
**Cause**: Scoring algorithm not correctly identifying the name
**Solution**:
- Adjust scoring weights
- Add more specific label patterns
- Check if Bengali character ratio is accurate

## Common Issues and Fixes

### Issue 1: Bengali OCR Returns English Text Only
**Symptom**: Raw OCR text contains only English characters
**Cause**: Tesseract using wrong language model
**Fix**: Verify `ben.traineddata` is in `assets/tessdata/`

### Issue 2: OCR Returns Garbled Bengali Text
**Symptom**: Bengali characters are incorrect or unreadable
**Cause**: Poor image quality or wrong Tesseract parameters
**Fix**:
- Try different `psm` values (3, 6, 11, 12)
- Improve image lighting and focus
- Pre-process image (contrast enhancement)

### Issue 3: Name Label Pattern Matches Actual Name
**Symptom**: Line with actual name is skipped as "label"
**Cause**: Label pattern too broad
**Fix**: Make label patterns more specific (e.g., exact match for "নাম:" with colon)

### Issue 4: Short Names Filtered Out
**Symptom**: Short Bengali names (2-3 chars) are skipped
**Cause**: Minimum length threshold too high
**Fix**: Reduce minimum length threshold from 2 to 1

## Next Steps After Getting Logs

1. **Copy the raw Bengali OCR text** from the logs
2. **Share the complete debug output** including:
   - Raw Bengali OCR text section
   - Line-by-line analysis
   - Candidate list with scores
3. **Based on the output**, I can:
   - Adjust label patterns to match actual NID format
   - Modify scoring algorithm
   - Change Tesseract parameters
   - Add preprocessing if needed

## Files Modified

1. **`lib/services/nid_ocr_service.dart`**
   - Enhanced Bengali OCR logging with raw text output
   - Improved `_extractBanglaName()` with detailed candidate analysis
   - Added ranking and scoring visualization
   - Logs all candidates with their scores

## Expected Log Output (Working Case)

```
=== NID OCR Started ===
Image path: /path/to/image.jpg
Tessdata path: /path/to/tessdata
Tessdata files: eng.traineddata, ben.traineddata
Running Google ML Kit Latin OCR...
Latin OCR result: 123 characters
Latin OCR text: NAME: MST. SADIA AKTER MON
...
Running Tesseract Bengali OCR...
Bengali OCR SUCCESS
Bengali OCR result length: 45 characters
=== RAW BENGALI OCR TEXT START ===
নাম: মোছাম্মদ সাদিয়া আক্তার মন
আইডি: 5117448281
=== RAW BENGALI OCR TEXT END ===
=== Extracting Bangla Name ===
Input text length: 45
Total lines after split: 2
Line 0: "নাম: মোছাম্মদ সাদিয়া আক্তার মন" (length: 35)
Line 1: "আইডি: 5117448281" (length: 12)
Line 0: Candidate - Original: "নাম: মোছাম্মদ সাদিয়া আক্তার মন", Cleaned: "মোছাম্মদ সাদিয়া আক্তার মন", Bengali chars: 27, Ratio: 0.77, Score: 347
Total candidates found: 1
Candidates ranked by score:
  Rank 0: "মোছাম্মদ সাদিয়া আক্তার মন" (score: 347)
Final Bangla name: "মোছাম্মদ সাদিয়া আক্তার মন"
OCR completed for front
NID number: 5117448281
English name: MST. SADIA AKTER MON
Bangla name: মোছাম্মদ সাদিয়া আক্তার মন
```

## Action Required

Please run the app, capture an NID image, and share the complete debug output. This will allow me to:
1. See the actual Bengali OCR output
2. Identify why extraction is failing
3. Apply the correct fix based on the real data
