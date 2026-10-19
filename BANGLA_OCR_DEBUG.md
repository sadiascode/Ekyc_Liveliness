# Bangla Name Extraction - Debugging Guide

## Root Cause Analysis

The Bangla name extraction was failing due to several issues:

1. **Insufficient Debug Logging**: The original implementation silently caught Tesseract OCR errors without logging, making it impossible to diagnose whether:
   - Tesseract was initialized successfully
   - The trained data files were loaded
   - OCR was actually running
   - The extracted text contained Bengali characters

2. **Oversimplified Extraction Logic**: The original `_extractBanglaName()` method:
   - Only checked for the presence of Bengali characters
   - Didn't filter out Bengali labels (নাম, আইডি, etc.)
   - Didn't score lines to find the most likely name
   - Didn't clean noise from OCR output

3. **Asset Configuration**: The pubspec.yaml didn't explicitly include the `tessdata_config.json` file.

## Files Changed

### 1. `lib/services/nid_ocr_service.dart`
- Added comprehensive debug logging for:
  - Image path verification
  - Tesseract tessdata path and file listing
  - Latin OCR output
  - Bengali OCR output (with character count and full text)
  - Extraction process (line-by-line analysis)
  - Error stack traces
- Added Tesseract path verification to ensure assets are loaded
- Improved `_extractBanglaName()` with:
  - Bengali label pattern matching (নাম, আইডি, তারিখ, etc.)
  - Scoring system to select the best candidate
  - Better text cleaning (removing non-Bengali chars, normalizing whitespace)
  - Detailed debug output for each line analyzed
- Added Tesseract parameters: `psm: 6` (single uniform block) and `preserve_interword_spaces: 1`

### 2. `pubspec.yaml`
- Added explicit asset path for `tessdata_config.json`
- Ensured `assets/tessdata/` is included

### 3. `assets/tessdata/`
- Added `eng.traineddata` (English language model)
- Added `ben.traineddata` (Bengali language model)

### 4. `assets/tessdata_config.json`
- Configuration file listing the trained data files

## Testing Bangla Name Extraction

### Prerequisites
1. Ensure you have a real Bangladesh NID card image
2. Run `flutter pub get` to ensure dependencies are installed
3. Build the app on a physical device (emulator may have OCR issues)

### Testing Steps

#### Step 1: Run the App with Debug Mode
```bash
flutter run
```

#### Step 2: Capture NID Front
1. Navigate to the NID capture screen
2. Capture the front of a Bangladesh NID card
3. Ensure the image is clear and well-lit

#### Step 3: Check Debug Logs
In your terminal, look for the following debug output:

```
=== NID OCR Started ===
Image path: /path/to/image.jpg
Tessdata path: /path/to/tessdata
Tessdata files: /path/to/tessdata/eng.traineddata, /path/to/tessdata/ben.traineddata
Running Google ML Kit Latin OCR...
Latin OCR result: 123 characters
Latin OCR text: [English OCR output]
Running Tesseract Bengali OCR...
Bengali OCR result: 45 characters
Bengali OCR text: [Bengali OCR output]
=== Extracting Bangla Name ===
Input text: [Full Bengali OCR text]
Total lines: 10
Line 0: [First line]
...
Final Bangla name: [Extracted name]
```

#### Step 4: Verify Review Screen
1. Navigate to the Review Screen
2. Check the "Bangla Name" field
3. It should contain the extracted Bengali name
4. The field should be editable for manual correction

#### Step 5: Test Edge Cases
Test with different NID card types:
- Smart NID cards
- Laminated NID cards
- Cards with faded text
- Cards with glare

### Common Issues and Solutions

#### Issue: "Bengali OCR failed" in logs
**Cause**: Tesseract assets not properly loaded
**Solution**:
1. Verify `assets/tessdata/eng.traineddata` and `assets/tessdata/ben.traineddata` exist
2. Run `flutter clean && flutter pub get`
3. Rebuild the app: `flutter run`

#### Issue: Tessdata directory does not exist
**Cause**: iOS requires manual tessdata folder setup
**Solution** (iOS only):
1. Open `ios/Runner.xcworkspace` in Xcode
2. Drag the `assets/tessdata` folder into the Runner project
3. Ensure "Create folder references" is selected
4. Clean and rebuild

#### Issue: Bengali OCR returns empty text
**Cause**: Poor image quality or wrong Tesseract parameters
**Solution**:
1. Ensure the NID image is clear and well-lit
2. Try different `psm` values (3, 6, 11) in the OCR call
3. Pre-process the image (contrast enhancement, noise reduction)

#### Issue: Extraction returns wrong text (labels instead of name)
**Cause**: Label patterns not matching actual NID format
**Solution**:
1. Check the debug logs to see which lines are being considered
2. Add more label patterns to the `labelPatterns` array
3. Adjust the scoring threshold

#### Issue: Extraction returns null
**Cause**: No lines meet the minimum Bengali character threshold
**Solution**:
1. Check if Bengali OCR is actually returning Bengali text
2. Lower the minimum character threshold from 3 to 2
3. Verify the NID card actually has Bengali text

### Platform-Specific Notes

#### Android
- Tesseract assets are automatically copied from assets to the app's data directory
- No additional configuration needed beyond pubspec.yaml

#### iOS
- Requires manual tessdata folder setup in Xcode
- The `assets/tessdata` folder must be added as a folder reference, not a group
- See: https://pub.dev/packages/flutter_tesseract_ocr#ios-issues

### Performance Considerations
- Tesseract OCR is slower than Google ML Kit
- Bengali OCR may take 2-5 seconds on typical devices
- Consider showing a loading indicator during OCR processing

### Next Steps for Improvement
1. Add image preprocessing (contrast, noise reduction) before OCR
2. Implement region-based OCR (only OCR the name area)
3. Add confidence scoring for OCR results
4. Cache OCR results to avoid reprocessing
5. Consider using Tesseract Fast models for better performance
