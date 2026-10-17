import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// All captures live in a private temp folder (never the gallery) and are
/// wiped after submission or when the officer starts over.
class KycStorage {
  static Future<Directory> dir() async {
    final base = await getTemporaryDirectory();
    final d = Directory('${base.path}/kyc_session');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<void> wipe() async {
    final base = await getTemporaryDirectory();
    final d = Directory('${base.path}/kyc_session');
    if (await d.exists()) await d.delete(recursive: true);
  }
}

Future<void> deleteQuietly(String path) async {
  try {
    await File(path).delete();
  } catch (_) {}
}
