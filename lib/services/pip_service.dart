// Cross-platform Picture-in-Picture service.
//
// PiP is intentionally disabled for this build. The previous `floating`
// plugin still referenced the removed Android v1 Registrar API and prevented
// release builds from compiling. Keeping this service API-compatible lets
// callers remain unchanged while Android TV playback continues normally.

import 'dart:async';
import 'dart:io' show Platform;

class PipService {
  PipService._();
  static final PipService instance = PipService._();

  bool get isSupported => false;

  Future<bool> enter({int width = 16, int height = 9}) async => false;

  Future<bool> exit() async => false;

  Stream<bool> get pipStatusStream => const Stream<bool>.empty();

  Future<bool> toggle({int width = 16, int height = 9}) async => false;
}
