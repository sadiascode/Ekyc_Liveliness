# eKYC capture app (Flutter)

NID front and back capture with on-device quality checks, plus a live selfie
with randomized active liveness. Built for a bank officer or agent assisting
a customer.

## What it does

**NID capture** (back camera, 1080p)
- Card-shaped guide frame (ID-1, 85.6 x 54 mm); the photo is cropped to the frame
- Blur (Laplacian variance), exposure and glare checks run in a background isolate
- "Use this photo" stays disabled until the image passes
- Front side: ML Kit OCR reads NID number (10/13/17 digits), name and date of birth; the officer confirms them on the review screen

**Live selfie** (front camera, ML Kit face detection)
- 3 of 4 challenges in random order each attempt: blink, turn left, turn right, smile
- Each challenge starts from a neutral pose and must finish in 8 s (60 s per session)
- Blink must go open → closed → open; smile must start from a straight face
- Exactly one face, sized and centered in the oval; same tracked face throughout
- Final photo is taken only after a stable, front-facing, eyes-open pose, then re-checked
- Leaving the app mid-session restarts it

**Handling data**
- Images live in the app's temp folder, never the gallery, and are wiped after submit or "Start over"
- Multipart upload to your API; demo mode when no URL is set

## Run

```bash
flutter create . --org com.yourbank --platforms android,ios   # adds android/ and ios/ folders
flutter pub get
flutter run                                                    # demo mode
flutter run --dart-define=KYC_API_BASE_URL=https://api.yourbank.com.bd
```

## Platform setup

### Android
`android/app/build.gradle(.kts)`: `minSdk = 24` (or higher).

`android/app/src/main/AndroidManifest.xml`, above `<application>`:
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-feature android:name="android.hardware.camera" android:required="true" />
```

Block screenshots and screen recording (recommended for banking), in
`android/app/src/main/kotlin/.../MainActivity.kt`:
```kotlin
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
```

### iOS
`ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>The camera is used to photograph your national ID and take a live selfie for identity verification.</string>
```
`ios/Podfile`: `platform :ios, '15.5'` (ML Kit minimum). Test on a real device.

## Tuning

| Setting | File | Default |
|---|---|---|
| Blur / brightness / glare thresholds | `services/image_quality_service.dart` | 80 / 60–215 / 6% |
| Challenge count, timeouts | `services/liveness_engine.dart` | 3, 8 s, 60 s |
| Head-turn angle | `liveness_engine.dart` `_turnDeg` | 25° |
| Left/right direction | `LivenessEngine.yawSign` | 1.0 |

Test "turn left / turn right" on your target phones first. If they feel
swapped, set `yawSign = -1.0`.

## Laravel endpoint (matches the app's request)

```php
// routes/api.php
Route::post('/v1/kyc/submissions', [KycSubmissionController::class, 'store'])
    ->middleware(['auth:sanctum', 'throttle:10,1']);

// app/Http/Controllers/KycSubmissionController.php
public function store(Request $request)
{
    $data = $request->validate([
        'nid_number'    => ['required', 'regex:/^(\d{10}|\d{13}|\d{17})$/'],
        'full_name'     => ['required', 'string', 'max:150'],
        'date_of_birth' => ['required', 'date_format:Y-m-d', 'before:today'],
        'mobile'        => ['required', 'regex:/^01[3-9]\d{8}$/'],
        'consent'       => ['accepted'],
        'liveness'      => ['required', 'json'],
        'nid_front'     => ['required', 'file', 'mimes:jpg,jpeg', 'max:5120'],
        'nid_back'      => ['required', 'file', 'mimes:jpg,jpeg', 'max:5120'],
        'selfie'        => ['required', 'file', 'mimes:jpg,jpeg', 'max:5120'],
    ]);

    $id = (string) Str::uuid();
    $paths = [];
    foreach (['nid_front', 'nid_back', 'selfie'] as $field) {
        // 'kyc' = private disk, encrypted at rest, never publicly served
        $paths[$field] = $request->file($field)->storeAs("kyc/{$id}", "{$field}.jpg", 'kyc');
    }

    $submission = KycSubmission::create([
        'id'            => $id,
        'user_id'       => $request->user()->id,
        'nid_number'    => $data['nid_number'],
        'full_name'     => $data['full_name'],
        'date_of_birth' => $data['date_of_birth'],
        'mobile'        => $data['mobile'],
        'liveness_meta' => json_decode($data['liveness'], true),
        'files'         => $paths,
        'status'        => 'pending_verification',
    ]);

    VerifyKycSubmission::dispatch($submission); // EC NID check + face match, async

    return response()->json(['id' => $id, 'status' => 'pending_verification'], 201);
}
```

## Before production

This app gives you **active liveness on the device**. That stops printed
photos and casual misuse, but a determined attacker can replay a video or use
a modified device. For a bank, treat the app's result as one signal and add
server-side checks:

1. **Passive liveness / anti-spoofing on the server** (texture, depth and
   replay detection) using a certified vendor SDK or service.
2. **Face match** between the selfie and the NID photo, and ideally against
   the Election Commission photo through the EC NID verification service your
   bank is licensed for.
3. **Data checks** of NID number, name and DOB against EC records.
4. **App integrity**: Play Integrity API / App Attest, root/jailbreak
   detection, certificate pinning, and short-lived tokens from your login.
5. **Audit trail**: officer ID, device ID, timestamps, and the liveness
   metadata the app already sends.
6. Align the flow and data retention with Bangladesh Bank's e-KYC guidelines
   and your compliance team's requirements.
