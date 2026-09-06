import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Launches the native Media3 player used by the Google TV build.
///
/// Stremio uses Media3/ExoPlayer for its Android TV internal player. Keeping
/// this bridge small lets the TV receive Android's normal D-pad and media-key
/// events instead of translating them through Flutter gesture controls.
class TvExoPlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  final String? audioUrl;
  final Map<String, String>? headers;
  final Duration? startPosition;
  final Future<void> Function(Duration position, Duration duration)? onSaveProgress;

  const TvExoPlayerScreen({
    super.key,
    required this.url,
    required this.title,
    this.audioUrl,
    this.headers,
    this.startPosition,
    this.onSaveProgress,
  });

  @override
  State<TvExoPlayerScreen> createState() => _TvExoPlayerScreenState();
}

class _TvExoPlayerScreenState extends State<TvExoPlayerScreen> {
  static const _channel = MethodChannel('com.example.play_torrio_native/tv_player');
  bool _launching = true;
  bool _returned = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openNativePlayer());
  }

  Future<void> _openNativePlayer() async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'openExoPlayer',
        <String, Object?>{
          'url': widget.url,
          'title': widget.title,
          'audioUrl': widget.audioUrl,
          'startPositionMs': widget.startPosition?.inMilliseconds ?? 0,
          'headers': widget.headers ?? const <String, String>{},
        },
      );
      if (_returned || !mounted) return;
      _returned = true;
      final position = _durationFromResult(result, 'positionMs');
      final duration = _durationFromResult(result, 'durationMs');
      if (position > Duration.zero && widget.onSaveProgress != null) {
        try {
          await widget.onSaveProgress!(position, duration);
        } catch (error) {
          debugPrint('[TvExoPlayer] Progress save failed: $error');
        }
      }
      if (mounted) Navigator.of(context).pop(position);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _launching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('TV player could not start: ${error.message ?? error.code}')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _launching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('TV player could not start: $error')),
      );
    }
  }

  Duration _durationFromResult(Map<Object?, Object?>? result, String key) {
    final value = result?[key];
    return value is num ? Duration(milliseconds: value.toInt()) : Duration.zero;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _launching
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF7C4DFF)),
                  SizedBox(height: 18),
                  Text(
                    'Opening TV player…',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              )
            : Focus(
                autofocus: true,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.goBack ||
                          event.logicalKey == LogicalKeyboardKey.browserBack ||
                          event.logicalKey == LogicalKeyboardKey.escape)) {
                    Navigator.of(context).pop();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: const Text(
                  'TV player unavailable',
                  style: TextStyle(color: Colors.white70, fontSize: 18),
                ),
              ),
      ),
    );
  }
}
