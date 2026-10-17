import 'package:camera/camera.dart';

String cameraErrorMessage(CameraException e) {
  switch (e.code) {
    case 'CameraAccessDenied':
    case 'CameraAccessDeniedWithoutPrompt':
    case 'CameraAccessRestricted':
      return 'Camera access is off. Allow camera access for this app in Settings, then try again.';
    default:
      return 'The camera could not start (${e.code}). Close other apps using the camera and try again.';
  }
}
