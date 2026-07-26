# Media Manager

A Flutter Android app for managing your [Radarr](https://radarr.video) and
[Sonarr](https://sonarr.tv) servers from your phone: browse your library,
search for new movies and shows, and add them with a chosen quality profile
and root folder.

## Features

- **Movies tab** — your Radarr library with posters and download status
- **TV Shows tab** — your Sonarr library
- **Add new** — tap **+** on either tab to search TMDB/TVDB (via your
  server's lookup API) and add items, with quality profile / root folder
  selection and an optional immediate download search
- **Settings tab** — server URL + API key for each service, with a
  connection test; keys are stored in Android encrypted storage

## Setup

1. In Radarr/Sonarr, copy the API key from **Settings → General → API Key**.
2. In the app's Settings tab, enter each server's URL (e.g.
   `http://192.168.1.10:7878` for Radarr, `:8989` for Sonarr) and API key,
   then **Test** and **Save**.

The app talks directly to your servers, so your phone must be able to reach
them — on the same LAN, or via a VPN such as WireGuard/Tailscale when away
from home.

## Development

```sh
flutter pub get
flutter run          # with a device or emulator connected
flutter build apk    # release APK in build/app/outputs/flutter-apk/
```

Note for this machine: AVG Antivirus intercepts HTTPS with its own root
certificate, which Java doesn't trust by default. Build with a trust store
that includes AVG's root:

```powershell
$env:JAVA_TOOL_OPTIONS = "-Djavax.net.ssl.trustStore=C:\Users\dpbre\dev\cacerts-with-avg -Djavax.net.ssl.trustStorePassword=changeit"
```

## Structure

- `lib/api/arr_api.dart` — shared Radarr/Sonarr v3 API client
- `lib/models/` — `ServerConfig`, unified `MediaItem` (movie or series)
- `lib/state/app_state.dart` — per-service state (config + library cache)
- `lib/screens/` — library, add-search, and settings screens

## Releases & in-app updates

The app is sideloaded (not on the Play Store), so it updates itself. On launch and
from **Settings → App updates**, `lib/services/update_service.dart` checks the latest
release of this repo (`ArrHub-Apps/ArrHubMobile`), and if it's newer than the running
build, downloads the APK and hands it to Android's package installer (needs the
`REQUEST_INSTALL_PACKAGES` permission). Nothing installs silently — the user opts in
and confirms in the system UI.

> ⚠️ The update check reads the repo's Releases anonymously, so it only works once
> this repo is **public**. (Previously releases went to a separate public
> `MobileReleases` repo while this one was private; that's no longer needed.)

### Cutting a release

Releases are built and published by `.github/workflows/release.yml` on a version tag:

1. Bump `version` in `pubspec.yaml`, commit.
2. Tag and push: `git tag v0.2.0 && git push origin v0.2.0`.
3. CI builds a **signed** release APK and publishes it to this repo's Releases.

**Signing is mandatory and must be stable.** Android refuses an update whose signature
doesn't match the installed app, so every release is signed with the *same* keystore.
Locally that's `android/key.properties` (gitignored) + your keystore; in CI it's
reconstructed from repo secrets:

| Secret | What |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | the `.jks` keystore, base64-encoded |
| `ANDROID_KEYSTORE_PASSWORD` | store password |
| `ANDROID_KEY_PASSWORD` | key password |
| `ANDROID_KEY_ALIAS` | key alias |

CI publishes to this repo's own Releases, so the built-in `GITHUB_TOKEN` (granted
`contents: write` in the workflow) is used — no PAT is needed.

Generate the keystore once (`keytool -genkey -v -keystore upload-keystore.jks -keyalg
RSA -keysize 2048 -validity 10000 -alias upload`), keep it safe, and base64 it into
`ANDROID_KEYSTORE_BASE64`. Losing it means users can't auto-update past that point.
