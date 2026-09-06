import 'dart:io';
import 'package:flutter/material.dart';
import 'package:play_torrio_native/models/movie.dart';
import 'package:play_torrio_native/models/stream_source.dart';
import '../services/external_player_service.dart';
import '../services/watch_history_service.dart';
import '../api/settings_service.dart';
import 'player/mobile_player_screen.dart';
import 'player/desktop_player_screen.dart';
import 'tv_exo_player_screen.dart';

class PlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String? audioUrl;
  final String title;
  final String? magnetLink;
  final Map<String, String>? headers;
  final Movie? movie;
  final Map<String, dynamic>? providers;
  final String? activeProvider;
  final int? selectedSeason;
  final int? selectedEpisode;
  final Duration? startPosition;
  final List<StreamSource>? sources;
  final int? fileIndex;
  final List<Map<String, dynamic>>? externalSubtitles;
  final String? stremioId;
  final String? stremioAddonBaseUrl;

  /// External next-episode handler. When provided, the in-player "Next
  /// Episode" button will route through this callback instead of running the
  /// built-in TMDB / torrent / WebStreamr resolution. Used by anime so the
  /// resolver can re-race all sources for the next episode.
  final Future<void> Function()? onNextEpisode;
  final bool hasNextEpisode;

  /// Optional progress save hook. Called by the inner player when the
  /// watch history should be persisted (lifecycle pause, periodic tick,
  /// player exit). Used by anime / arabic flows that own their own
  /// per-source history store and don't go through `WatchHistoryService`.
  final Future<void> Function(Duration position, Duration duration)? onSaveProgress;

  const PlayerScreen({
    super.key,
    required this.streamUrl,
    this.audioUrl,
    required this.title,
    this.magnetLink,
    this.headers,
    this.movie,
    this.providers,
    this.activeProvider,
    this.selectedSeason,
    this.selectedEpisode,
    this.startPosition,
    this.sources,
    this.fileIndex,
    this.externalSubtitles,
    this.stremioId,
    this.stremioAddonBaseUrl,
    this.onNextEpisode,
    this.hasNextEpisode = false,
    this.onSaveProgress,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool _useExternalPlayer = false;
  bool _externalLaunched = false;
  bool _checkingPlayer = true;
  String _externalPlayerName = '';

  @override
  void initState() {
    super.initState();
    _checkExternalPlayer();
  }

  Future<void> _checkExternalPlayer() async {
    try {
      final playerName = await SettingsService().getExternalPlayer();
      final isExternal = playerName != 'Built-in Player' && !_isGoogleTvContext;

      if (!mounted) return;

      if (isExternal) {
        setState(() {
          _useExternalPlayer = true;
          _externalPlayerName = playerName;
          _checkingPlayer = false;
        });
        _launchExternal();
      } else {
        setState(() {
          _useExternalPlayer = false;
          _checkingPlayer = false;
        });
      }
    } catch (error) {
      debugPrint('[PlayerScreen] External player preference failed: $error');
      if (mounted) setState(() => _checkingPlayer = false);
    }
  }

  Future<void> _launchExternal() async {
    final success = await ExternalPlayerService.launch(
      url: widget.streamUrl,
      title: widget.title,
      headers: widget.headers,
      context: context,
    );

    if (!mounted) return;

    if (success) {
      setState(() => _externalLaunched = true);
    } else {
      // Player not found — fall back to built-in player
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$_externalPlayerName not found. Using built-in player.',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.orange.shade900,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() {
        _useExternalPlayer = false;
        _externalLaunched = false;
      });
    }
  }

  Future<void> _saveTvProgress(Duration position, Duration duration) async {
    final movie = widget.movie;
    if (movie == null || position.inMilliseconds < 10_000 || duration.inMilliseconds <= 0) {
      return;
    }

    final isTorrent = widget.magnetLink != null;
    final isStremioDirect = widget.activeProvider == 'stremio_direct';
    final String method;
    final String sourceId;
    if (isTorrent) {
      method = 'torrent';
      sourceId = widget.magnetLink!;
    } else if (isStremioDirect) {
      method = 'stremio_direct';
      sourceId = widget.streamUrl;
    } else if (widget.activeProvider == 'amri') {
      method = 'amri';
      sourceId = widget.streamUrl;
    } else if (widget.activeProvider != null) {
      method = 'stream';
      sourceId = widget.activeProvider!;
    } else {
      method = 'amri';
      sourceId = widget.streamUrl;
    }

    await WatchHistoryService().saveProgress(
      tmdbId: movie.id,
      imdbId: movie.imdbId,
      title: widget.title,
      posterPath: movie.posterPath,
      method: method,
      sourceId: sourceId,
      position: position.inMilliseconds,
      duration: duration.inMilliseconds,
      season: widget.selectedSeason,
      episode: widget.selectedEpisode,
      episodeTitle: widget.selectedEpisode == null
          ? null
          : 'Episode ${widget.selectedEpisode}',
      magnetLink: widget.magnetLink,
      fileIndex: widget.fileIndex,
      streamUrl: isStremioDirect ? widget.streamUrl : null,
      stremioId: widget.stremioId,
      stremioAddonBaseUrl: widget.stremioAddonBaseUrl,
      stremioType: movie.mediaType == 'tv' ? 'series' : 'movie',
      mediaType: movie.mediaType,
    );
  }

  bool get _isGoogleTvContext {
    if (!Platform.isAndroid) return false;
    final isTvBuild = const bool.fromEnvironment('PLAYTORRIO_GOOGLE_TV');
    final shortestSide = MediaQueryData.fromView(
        WidgetsBinding.instance.platformDispatcher.views.first,
      ).size.shortestSide;
    return isTvBuild || shortestSide >= 600;
  }

  bool _isGoogleTv(BuildContext context) {
    if (!Platform.isAndroid) return false;
    return const bool.fromEnvironment('PLAYTORRIO_GOOGLE_TV') ||
        MediaQuery.sizeOf(context).shortestSide >= 600;
  }

  @override
  Widget build(BuildContext context) {
    // Still checking settings
    if (_checkingPlayer) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
        ),
      );
    }

    // External player mode — show a "playing externally" screen
    if (_useExternalPlayer) {
      return _ExternalPlayerWaitScreen(
        title: widget.title,
        playerName: _externalPlayerName,
        streamUrl: widget.streamUrl,
        launched: _externalLaunched,
        onRelaunch: _launchExternal,
        onSwitchBuiltIn: () {
          setState(() {
            _useExternalPlayer = false;
            _externalLaunched = false;
          });
        },
      );
    }

    // The Google TV flavor uses native Media3/ExoPlayer, matching Stremio's
    // Android TV player family and giving the remote a native media surface.
    if (_isGoogleTv(context)) {
      return TvExoPlayerScreen(
        url: widget.streamUrl,
        title: widget.title,
        audioUrl: widget.audioUrl,
        headers: widget.headers,
        startPosition: widget.startPosition,
        onSaveProgress: widget.onSaveProgress ?? _saveTvProgress,
      );
    }

    // Built-in player
    if (Platform.isAndroid || Platform.isIOS) {
      return MobilePlayerScreen(
        mediaPath: widget.streamUrl,
        title: widget.title,
        audioUrl: widget.audioUrl,
        headers: widget.headers,
        movie: widget.movie,
        selectedSeason: widget.selectedSeason,
        selectedEpisode: widget.selectedEpisode,
        magnetLink: widget.magnetLink,
        activeProvider: widget.activeProvider,
        startPosition: widget.startPosition,
        sources: widget.sources,
        fileIndex: widget.fileIndex,
        externalSubtitles: widget.externalSubtitles,
        stremioId: widget.stremioId,
        stremioAddonBaseUrl: widget.stremioAddonBaseUrl,
        providers: widget.providers,
        onNextEpisode: widget.onNextEpisode,
        hasNextEpisode: widget.hasNextEpisode,
        onSaveProgress: widget.onSaveProgress,
      );
    } else {
      return DesktopPlayerScreen(
        mediaPath: widget.streamUrl,
        title: widget.title,
        audioUrl: widget.audioUrl,
        headers: widget.headers,
        movie: widget.movie,
        selectedSeason: widget.selectedSeason,
        selectedEpisode: widget.selectedEpisode,
        magnetLink: widget.magnetLink,
        activeProvider: widget.activeProvider,
        startPosition: widget.startPosition,
        sources: widget.sources,
        fileIndex: widget.fileIndex,
        externalSubtitles: widget.externalSubtitles,
        stremioId: widget.stremioId,
        stremioAddonBaseUrl: widget.stremioAddonBaseUrl,
        providers: widget.providers,
        onNextEpisode: widget.onNextEpisode,
        hasNextEpisode: widget.hasNextEpisode,
        onSaveProgress: widget.onSaveProgress,
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  EXTERNAL PLAYER WAIT SCREEN
//
//  Shown while the video is playing in an external app. Keeps the app alive
//  (and the torrent engine streaming) while the user watches elsewhere.
// ─────────────────────────────────────────────────────────────────────────────

class _ExternalPlayerWaitScreen extends StatelessWidget {
  final String title;
  final String playerName;
  final String streamUrl;
  final bool launched;
  final VoidCallback onRelaunch;
  final VoidCallback onSwitchBuiltIn;

  const _ExternalPlayerWaitScreen({
    required this.title,
    required this.playerName,
    required this.streamUrl,
    required this.launched,
    required this.onRelaunch,
    required this.onSwitchBuiltIn,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.open_in_new_rounded,
                    color: Color(0xFF7C3AED),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 24),

                // Title
                Text(
                  launched ? 'Playing in $playerName' : 'Launching $playerName...',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Subtitle
                Text(
                  title,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),

                // Info text
                Text(
                  launched
                      ? 'The stream is being kept alive.\nYou can go back when you\'re done watching.'
                      : 'Opening the video in the external player...',
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),

                // Action buttons
                if (launched) ...[
                  // Re-launch button
                  SizedBox(
                    width: 260,
                    child: OutlinedButton.icon(
                      onPressed: onRelaunch,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: Text('Re-launch in $playerName'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF7C3AED),
                        side: const BorderSide(color: Color(0xFF7C3AED)),
                        padding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Switch to built-in button
                  SizedBox(
                    width: 260,
                    child: TextButton.icon(
                      onPressed: onSwitchBuiltIn,
                      icon: const Icon(Icons.play_circle_outline, size: 20),
                      label: const Text('Use Built-in Player Instead'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white54,
                        padding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 20),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 32),

                // Back button
                SizedBox(
                  width: 260,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                    label: const Text('Go Back'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
