// Cross-platform Picture-in-Picture service.
//
// PiP is intentionally disabled for this build. The previous `floating`
// plugin still referenced the removed Android v1 Registrar API and prevented
// release builds from compiling. Keeping this service API-compatible lets
// callers remain unchanged while Android TV playback continues normally.

import 'dart:async';

class PipService {
  PipService._();
  static final PipService instance = PipService._();

  bool get isSupported => false;
  bool get isDesktopActive => false;

  Stream<bool> get androidPipChanges => const Stream<bool>.empty();
  Stream<bool> get desktopPipChanges => const Stream<bool>.empty();
  Stream<bool> get pipStatusStream => const Stream<bool>.empty();

  Future<bool> enter({int width = 16, int height = 9}) async => false;

  Future<bool> exit() async => false;
  Future<bool> leave() async => false;

  Future<bool> toggle({int width = 16, int height = 9}) async => false;
}
