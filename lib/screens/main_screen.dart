import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'home_screen.dart';
import 'discover_screen.dart';
import 'search_screen.dart';
import 'my_list_screen.dart';
import 'settings_screen.dart';
import 'music_screen.dart';
import 'audiobook_screen.dart';
import 'books_screen.dart';
import 'comics_screen.dart';
import 'manga_screen.dart';
import 'jellyfin_screen.dart';
import 'anime_screen.dart';
import 'anime_arabic_screen.dart';
import 'asian_drama_screen.dart';
import 'similar/similar_hub_screen.dart';
import 'media_downloader_screen.dart';
import 'arabic_screen.dart';
import 'live_matches_screen.dart';
import 'magnet_player_screen.dart';
import '../features/iptv/playtorrio_tv/screens/iptv_pt_screen.dart';
import '../utils/app_theme.dart';
import '../api/settings_service.dart';
import '../services/app_updater_service.dart';
import '../widgets/update_dialog.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  /// Notifier that SearchScreen listens to for incoming Stremio search requests.
  /// Value is {'query': '...', 'addonBaseUrl': '...'} or null.
  static final ValueNotifier<Map<String, String>?> stremioSearchNotifier = ValueNotifier<Map<String, String>?>(null);

  /// Anywhere in the app: `MainScreen.requestTab.value = 'home';` to switch tab.
  static final ValueNotifier<String?> requestTab = ValueNotifier<String?>(null);

  static State<MainScreen>? of(BuildContext context) {
    return context.findAncestorStateOfType<_MainScreenState>();
  }

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  final FocusNode _tvNavigationFocus = FocusNode(debugLabel: 'tv-navigation');
  final FocusScopeNode _tvContentFocusScope = FocusScopeNode(debugLabel: 'tv-content');
  final ScrollController _tvRailScrollController = ScrollController();
  final Map<String, FocusNode> _tvRailFocusNodes = {};
  bool _tvRailHasFocus = true;
  bool _isGoogleTv = false;
  // Legacy dashboard state is retained for the non-TV keyboard layout.
  int _dashboardIndex = 0;
  Timer? _metricsDebounce;
  Timer? _metricsSafety;

  /// All screens keyed by nav ID — created once, never recreated.
  late final Map<String, Widget> _allScreens;

  /// Nav item metadata keyed by nav ID.
  static const Map<String, Map<String, dynamic>> _navMeta = {
    'home':         {'icon': Icons.home_outlined,              'active': Icons.home,                    'label': 'Home'},
    'discover':     {'icon': Icons.explore_outlined,            'active': Icons.explore,                 'label': 'Discover'},
    'similar':      {'icon': Icons.auto_awesome_outlined, 'active': Icons.auto_awesome, 'label': 'Similar'},
    'downloader':   {'icon': Icons.cloud_download_outlined, 'active': Icons.cloud_download, 'label': 'Media Downloader'},
    'search':       {'icon': Icons.search,                      'active': Icons.search,                  'label': 'Search'},
    'mylist':       {'icon': Icons.bookmark_outline,            'active': Icons.bookmark,                'label': 'My List'},
    'magnet':       {'icon': Icons.link_rounded,                'active': Icons.link_rounded,            'label': 'Magnet'},
    'live_matches': {'icon': Icons.sports_soccer_outlined,      'active': Icons.sports_soccer_rounded,   'label': 'Live Matches'},
    'iptv':         {'icon': Icons.live_tv_outlined,            'active': Icons.live_tv,                 'label': 'IPTV'},
    'audiobooks':   {'icon': Icons.menu_book_outlined,          'active': Icons.menu_book,               'label': 'Audiobooks'},
    'books':        {'icon': Icons.import_contacts_rounded,     'active': Icons.import_contacts_rounded, 'label': 'Books'},
    'music':        {'icon': Icons.music_note_outlined,         'active': Icons.music_note,              'label': 'Music'},
    'comics':       {'icon': Icons.auto_stories_outlined,       'active': Icons.auto_stories,            'label': 'Comics'},
    'manga':        {'icon': Icons.book_outlined,               'active': Icons.book,                    'label': 'Manga'},
    'jellyfin':     {'icon': Icons.dns_outlined,                'active': Icons.dns_rounded,             'label': 'Jellyfin'},
    'anime':        {'icon': Icons.play_circle_outline,         'active': Icons.play_circle_filled,      'label': 'Anime'},
    'anime_arabic': {'icon': Icons.subtitles_outlined,           'active': Icons.subtitles,                'label': 'Anime Arabic'},
    'asian_drama':  {'icon': Icons.theater_comedy_outlined,     'active': Icons.theater_comedy,          'label': 'Asian Drama'},
    'arabic':       {'icon': Icons.movie_filter_outlined,       'active': Icons.movie_filter,            'label': 'Arabic'},
    'settings':     {'icon': Icons.settings_outlined,           'active': Icons.settings,                'label': 'Settings'},
  };

  /// Currently visible nav IDs (always ends with 'settings').
  List<String> _visibleIds = [..._defaultVisibleIdsForContext(), 'settings'];

  /// On Google TV builds we start with a smaller curated rail instead of the
  /// full desktop/phone nav set. Other items remain reachable through Search,
  /// within their own screens, or via Settings.
  static const List<String> _tvVisibleIds = [
    'home', 'discover', 'mylist', 'search', 'live_matches', 'iptv', 'music', 'settings',
  ];

  List<String> _defaultVisibleIdsForContext() {
    if (_isGoogleTv) {
      return _tvVisibleIds;
    }
    return SettingsService.allNavIds;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MainScreen.stremioSearchNotifier.addListener(_onStremioSearch);
    MainScreen.requestTab.addListener(_onRequestTab);
    SettingsService.navbarChangeNotifier.addListener(_onNavbarConfigChanged);

    _allScreens = {
      'home':         const HomeScreen(),
      'discover':     const DiscoverScreen(),
      'similar':      const SimilarHubScreen(),
      'downloader':   const MediaDownloaderScreen(),
      'search':       const SearchScreen(),
      'mylist':       const MyListScreen(),
      'magnet':       const MagnetPlayerScreen(),
      'live_matches': const LiveMatchesScreen(),
      'iptv':         const IptvPtScreen(),
      'audiobooks':   const AudiobookScreen(),
      'books':        const BooksScreen(),
      'music':        const MusicScreen(),
      'comics':       ComicsScreen(initialSearch: null),
      'manga':        MangaScreen(initialSearch: null),
      'jellyfin':     const JellyfinScreen(),
      'anime':        const AnimeScreen(),
      'anime_arabic': const AnimeArabicScreen(),
      'asian_drama':  const AsianDramaScreen(),
      'arabic':       const ArabicScreen(),
      'settings':     const SettingsScreen(),
    };

    _loadNavbarConfig();
    _checkForUpdates();
    if (_isGoogleTv && _selectedIndex < 0) {
      _selectedIndex = _visibleIds.indexOf('home').clamp(0, _visibleIds.length - 1);
      _syncTvRailFocusNodes();
    }
    // The TV flavor sets this flag before Dart starts. The size fallback also
    // supports Android TV devices that do not expose a TV-specific feature.
    _isGoogleTv = const bool.fromEnvironment('PLAYTORRIO_GOOGLE_TV') ||
        MediaQueryData.fromView(
          WidgetsBinding.instance.platformDispatcher.views.first,
        ).size.shortestSide >= 600;
    _syncTvRailFocusNodes();
    if (_isGoogleTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _requestTvRailFocus('home');
      });
    }
  }

  Future<void> _checkForUpdates() async {
    try {
      final updater = AppUpdaterService();
      final updateInfo = await updater.checkForUpdates();
      if (updateInfo != null && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => UpdateDialog(updateInfo: updateInfo),
        );
      }
    } catch (e) {
      debugPrint('[MainScreen] Update check failed: $e');
    }
  }

  Future<void> _loadNavbarConfig() async {
    final visible = await SettingsService().getNavbarConfig();
    if (!mounted) return;
    setState(() {
      // Remember which screen we're currently on
      final currentId = _selectedIndex < _visibleIds.length
          ? _visibleIds[_selectedIndex]
          : null;
      final freshIds = _defaultVisibleIdsForContext();
      _visibleIds = [...freshIds, 'settings'];
      if (_isGoogleTv && currentId == null) {
        _selectedIndex = freshIds.indexOf('home').clamp(0, freshIds.length - 1);
      }
      _syncTvRailFocusNodes();
      // Try to stay on the same screen after reorder/hide
      if (currentId != null) {
        final newIndex = _visibleIds.indexOf(currentId);
        if (newIndex >= 0) {
          _selectedIndex = newIndex;
        } else if (_selectedIndex >= _visibleIds.length) {
          _selectedIndex = _visibleIds.length - 1;
        }
      } else if (_selectedIndex >= _visibleIds.length) {
        _selectedIndex = 0;
      }
    });
  }

  void _syncTvRailFocusNodes() {
    final validIds = _visibleIds.toSet();
    for (final id in _tvRailFocusNodes.keys.toList()) {
      if (!validIds.contains(id)) {
        _tvRailFocusNodes.remove(id)?.dispose();
      }
    }
    for (final id in _visibleIds) {
      _tvRailFocusNodes.putIfAbsent(
        id,
        () => FocusNode(debugLabel: 'tv-nav-$id'),
      );
    }
  }

  void _onNavbarConfigChanged() {
    _loadNavbarConfig();
  }

  /// Rotation on MediaTek/Transsion can cause a multi-second frame storm.
  /// Two-timer strategy:
  ///   1. Debounced timer (1.5s): resets on every metrics change, fires
  ///      after the storm quiets down.
  ///   2. Safety timer (4s): fires once after the FIRST metrics change—
  ///      never cancelled—so even if the storm outlasts the debounce,
  ///      a clean rebuild is guaranteed.
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // Debounced: fires 1.5s after the LAST metrics change.
    _metricsDebounce?.cancel();
    _metricsDebounce = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() {});
    });
    // Safety: fires 4s after the FIRST metrics change. Never cancelled.
    _metricsSafety ??= Timer(const Duration(seconds: 4), () {
      _metricsSafety = null;
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && Platform.isAndroid) {
      // Only re-apply immersive mode; do NOT reset preferred orientations
      // here — it interferes with the player's orientation lock when the
      // player is pushed on top of this screen.
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  void _onStremioSearch() {
    final data = MainScreen.stremioSearchNotifier.value;
    if (data == null || (data['query'] ?? '').isEmpty) return;
    final idx = _visibleIds.indexOf('search');
    if (idx != -1) {
      setState(() => _selectedIndex = idx);
      if (_isGoogleTv) _requestTvRailFocus('search');
    }
  }

  void _onRequestTab() {
    final id = MainScreen.requestTab.value;
    if (id == null) return;
    final idx = _visibleIds.indexOf(id);
    if (idx != -1 && mounted) {
      setState(() => _selectedIndex = idx);
      if (_isGoogleTv) _requestTvRailFocus(id);
    }
    MainScreen.requestTab.value = null;
  }

  void _onItemTapped(int index) {
    if (index < 0 || index >= _visibleIds.length) return;
    setState(() => _selectedIndex = index);
    if (_isGoogleTv) {
      _requestTvRailFocus(_visibleIds[index]);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tvNavigationFocus.requestFocus();
      });
    }
  }

  void _requestTvRailFocus([String? id]) {
    if (_tvRailFocusNodes.isEmpty) return;
    final targetId = id ?? _visibleIds[_selectedIndex.clamp(0, _visibleIds.length - 1).toInt()];
    final node = _tvRailFocusNodes[targetId];
    if (node == null) return;
    setState(() => _tvRailHasFocus = true);
    node.requestFocus();
    _scrollTvRailToSelected(targetId);
  }

  void _moveTvRail(int direction) {
    final currentId = _visibleIds[_selectedIndex.clamp(0, _visibleIds.length - 1).toInt()];
    final current = _visibleIds.indexOf(currentId);
    final next = (current + direction).clamp(0, _visibleIds.length - 1).toInt();
    setState(() => _selectedIndex = next);
    _requestTvRailFocus(_visibleIds[next]);
  }

  void _enterTvContent() {
    setState(() => _tvRailHasFocus = false);
    _tvContentFocusScope.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tvContentFocusScope.nextFocus();
    });
  }

  void _scrollTvRailToSelected(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_tvRailScrollController.hasClients) return;
      final index = _visibleIds.indexOf(id);
      if (index < 0) return;
      _tvRailScrollController.animateTo(
        (index * 56.0).clamp(0.0, _tvRailScrollController.position.maxScrollExtent).toDouble(),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
  }

  KeyEventResult _handleTvRailKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        _moveTvRail(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _moveTvRail(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _enterTvContent();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  KeyEventResult _handleTvContentKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.escape)) {
      _requestTvRailFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }


  void searchComics(String query) {
    final idx = _visibleIds.indexOf('comics');
    if (idx != -1) {
      setState(() => _selectedIndex = idx);
      if (_isGoogleTv) _requestTvRailFocus('comics');
    }
  }

  void searchManga(String query) {
    final idx = _visibleIds.indexOf('manga');
    if (idx != -1) {
      setState(() => _selectedIndex = idx);
      if (_isGoogleTv) _requestTvRailFocus('manga');
    }
  }

  @override
  void dispose() {
    _metricsDebounce?.cancel();
    _metricsSafety?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    MainScreen.stremioSearchNotifier.removeListener(_onStremioSearch);
    MainScreen.requestTab.removeListener(_onRequestTab);
    SettingsService.navbarChangeNotifier.removeListener(_onNavbarConfigChanged);
    _tvNavigationFocus.dispose();
    _tvContentFocusScope.dispose();
    _tvRailScrollController.dispose();
    for (final node in _tvRailFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;
    
    final bool useNavRail = isDesktop || isLandscape;

    if (_isGoogleTv) {
      return _buildTvShell();
    }

    return Focus(
      focusNode: _tvNavigationFocus,
      autofocus: false,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowRight) {
          _moveDashboard(1, 0);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          _moveDashboard(-1, 0);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          _moveDashboard(0, 1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          _moveDashboard(0, -1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA) {
          _onItemTapped(_dashboardIndex);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
      body: Stack(
        children: [
          // Base gradient
          Container(decoration: AppTheme.effectiveBackground),
          // Ambient glows (skipped in light mode)
          if (!AppTheme.isLightMode) ...[
          // Ambient purple glow – top-right
          Positioned(
            top: -80,
            right: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.current.primaryColor.withValues(alpha: 0.18),
                    AppTheme.current.primaryColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // Ambient cyan glow – bottom-left
          Positioned(
            bottom: 40,
            left: -80,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.current.accentColor.withValues(alpha: 0.08),
                    AppTheme.current.accentColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // Soft violet glow – center-left
          Positioned(
            top: MediaQuery.of(context).size.height * 0.35,
            left: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.current.primaryColor.withValues(alpha: 0.10),
                    AppTheme.current.primaryColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          ], // end light mode glow skip
          // Content layer
          Row(
            children: [
              if (useNavRail)
              SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height),
                  child: IntrinsicHeight(
                    child: NavigationRail(
                          backgroundColor: Colors.transparent,
                          selectedIndex: _selectedIndex,
                          onDestinationSelected: _onItemTapped,
                          labelType: NavigationRailLabelType.all,
                          indicatorColor: AppTheme.current.primaryColor,
                          selectedLabelTextStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          unselectedLabelTextStyle: const TextStyle(
                            color: Colors.white54,
                          ),
                          leading: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24.0),
                            child: Icon(
                              Icons.play_circle_fill,
                              color: AppTheme.current.primaryColor,
                              size: 48,
                            ),
                          ),
                          destinations: _visibleIds.map((id) {
                            final meta = _navMeta[id]!;
                            return NavigationRailDestination(
                              icon: Icon(meta['icon'] as IconData, color: Colors.white54),
                              selectedIcon: Icon(meta['active'] as IconData, color: Colors.white),
                              label: Text(meta['label'] as String),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                
            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: _visibleIds.map((id) => _allScreens[id]!).toList(),
              ),
            ),
          ],
        ),
        ],
      ),
      bottomNavigationBar: useNavRail
          ? null
          : _buildScrollableBottomNav(),
      ),
    );
  }

  void _moveDashboard(int dx, int dy) {
    // Kept for the compact/mobile keyboard layout. The TV layout uses the
    // dedicated rail movement below instead of a startup tile grid.
    if (dx == 0 && dy != 0 && _visibleIds.isNotEmpty) {
      final next = (_dashboardIndex + dy).clamp(0, _visibleIds.length - 1).toInt();
      setState(() => _dashboardIndex = next);
    }
  }

  Widget _buildTvShell() {
    final selectedId = _visibleIds[_selectedIndex.clamp(0, _visibleIds.length - 1).toInt()];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (_tvRailHasFocus) {
            Navigator.of(context).maybePop();
          } else {
            _requestTvRailFocus();
          }
        }
      },
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: Scaffold(
          body: Stack(
            children: [
              Container(decoration: AppTheme.effectiveBackground),
              SafeArea(
                child: Row(
                  children: [
                    _buildTvRail(selectedId),
                    Expanded(
                      child: FocusScope(
                        node: _tvContentFocusScope,
                        child: Focus(
                          onKeyEvent: _handleTvContentKey,
                          child: ClipRect(
                            child: IndexedStack(
                              index: _selectedIndex,
                              children: _visibleIds.map((id) => _allScreens[id]!).toList(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTvRail(String selectedId) {
    return Container(
      width: 232,
      decoration: BoxDecoration(
        color: AppTheme.current.bgDark.withValues(alpha: 0.94),
        border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 24, offset: Offset(8, 0)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 18, 22),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.current.primaryColor,
                        Color.lerp(AppTheme.current.primaryColor, AppTheme.current.accentColor, 0.45)!,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.current.primaryColor.withValues(alpha: 0.35),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 25),
                ),
                const SizedBox(width: 11),
                const Expanded(
                  child: Text(
                    'PLAYTORRIO',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Text(
              'BROWSE',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.32),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Scrollbar(
              controller: _tvRailScrollController,
              thumbVisibility: true,
              child: ListView.builder(
                controller: _tvRailScrollController,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _visibleIds.length,
                itemBuilder: (context, index) {
                  final id = _visibleIds[index];
                  final meta = _navMeta[id]!;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: FocusableControl(
                      key: ValueKey('tv-nav-$id'),
                      focusNode: _tvRailFocusNodes[id],
                      onTap: () => _onItemTapped(index),
                      onKeyEvent: _handleTvRailKey,
                      borderRadius: 13,
                      glowColor: AppTheme.current.primaryColor,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 50,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: selectedId == id
                              ? AppTheme.current.primaryColor.withValues(alpha: 0.18)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: selectedId == id
                                ? AppTheme.current.primaryColor.withValues(alpha: 0.5)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              (selectedId == id ? meta['active'] : meta['icon']) as IconData,
                              color: selectedId == id
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.58),
                              size: 21,
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Text(
                                meta['label'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selectedId == id
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.66),
                                  fontSize: 14,
                                  fontWeight: selectedId == id
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            if (selectedId == id)
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: AppTheme.current.accentColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
            child: Text(
              _tvRailHasFocus
                  ? 'RIGHT  Open content'
                  : 'LEFT  Open navigation',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildScrollableBottomNav() {
    final lightMode = AppTheme.isLightMode;

    Widget navContent = Container(
          height: 80,
          decoration: BoxDecoration(
            color: AppTheme.current.bgDark.withValues(alpha: lightMode ? 1.0 : 0.75),
            border: const Border(top: BorderSide(color: Colors.white10, width: 0.5)),
          ),
          child: Stack(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: _visibleIds.asMap().entries.map((entry) {
                final int idx = entry.key;
                final String id = entry.value;
                final meta = _navMeta[id]!;
                final bool isSelected = _selectedIndex == idx;

                return InkWell(
                  onTap: () => _onItemTapped(idx),
                  child: Container(
                    width: 100,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.current.primaryColor.withValues(alpha: 0.2) : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            isSelected ? meta['active'] as IconData : meta['icon'] as IconData,
                            color: isSelected ? Colors.white : Colors.white54,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          meta['label'] as String,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white54,
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          if (!lightMode)
          Positioned(
            right: 0, top: 0, bottom: 0,
            child: IgnorePointer(
              child: Container(
                width: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Colors.transparent, AppTheme.current.bgDark.withValues(alpha: 0.7)],
                  ),
                ),
                child: const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white24),
              ),
            ),
          ),
        ],
      ),
    );

    if (lightMode) {
      return ClipRect(child: navContent);
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: navContent,
      ),
    );
  }
}
