# PlayTorrio

Stream anything, anywhere. Movies, TV shows, music, manga, comics, audiobooks, live sports. All in one app.

Made by me. If you like it, star it or whatever.

## What it does

Movies & TV Shows:
- Search and browse movies/TV shows with TMDB metadata
- Stream torrents directly with built-in libtorrent engine
- Stremio addon support
- Real-Debrid and TorBox integration
- Auto-resume from where you left off
- Watch history tracking
- Jellyfin server integration

Music:
- Search and stream music from Deezer
- Fetches audio from YouTube
- Synced lyrics
- Create playlists
- Download tracks for offline playback
- Like songs and save albums
- Full-featured player with shuffle, repeat, queue management

Manga & Comics:
- Read manga from multiple sources
- comics support
- Chapter tracking and history
- page-by-page or continuous scroll reading

Audiobooks:
- Stream audiobooks
- Chapter navigation
- Playback speed control

Live Sports:
- Watch live matches and events
- Multiple stream sources

IPTV:
- Xtream Codes API support
- M3U playlist support
- Live TV and VOD

Other stuff:
- Torrent search with Prowlarr/Jackett integration
- Auto-updates (checks on launch)
- Cross-platform (Windows, Linux, macOS, Android)
- Dark theme because obviously

## Download

Check the releases page for the latest builds.

Android builds:

```bash
# Google TV / Android TV devices with 32-bit ARMv7 CPUs
flutter build apk --release --flavor googleTv32 \
  --target-platform android-arm \
  --dart-define=PLAYTORRIO_GOOGLE_TV=true

# Modern 64-bit ARM Android devices
flutter build apk --release --flavor universal \
  --target-platform android-arm64
```

The Google TV flavor uses AndroidX Media3/ExoPlayer for its built-in video
player, matching the player family used by Stremio Android TV. The native
player handles Android TV D-pad and media-key events directly; mobile and
desktop builds continue to use the existing media_kit player.


You need Flutter and the usual build tools.

```
flutter pub get
flutter build windows
flutter build linux
flutter build apk
```

## License


GPL-2.0 license