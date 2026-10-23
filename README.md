# TuneFlow — Flutter client

The TuneFlow mobile client: **Flutter + Riverpod + Dio**, organised as feature-first clean
architecture with a cross-feature player service and a persistent mini-player.

Talks to the TuneFlow backend (`../backend`) over `/api/v1`.

---

## Status

| Check | Result |
|---|---|
| `flutter analyze` | **No issues found** (96 Dart files, `strict-casts` + `strict-raw-types`, no lint exceptions) |
| `flutter test` | **105 / 105 passing** (unit + widget, including the router configuration suite, the chunked-upload planner and the two flows below) |
| Dart / Flutter | Dart 3.13.5, Flutter 3.47.6 stable |
| Platforms scaffolded | `android/`, `ios/`, `web/` |

A release web bundle compile (`flutter build web --release`) was attempted as an extra whole-tree
compile proof but the sandbox has ~1 GB of RAM, and `dart2js` is OOM-killed on this project size.
That is an environment limit rather than a code problem — the analyzer resolves and type-checks the
entire tree, including unused-to-bytecode paths, and the widget tests build the real widget tree.

---

## Running it

```bash
flutter pub get

# Android emulator (host loopback alias)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1

# iOS simulator / desktop / a device on the same network
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8080/api/v1

# against a deployed API
flutter run --dart-define=API_BASE_URL=https://api.tuneflow.example/api/v1
```

Configuration is injected at compile time (`AppConfig.fromEnvironment`) so no `.env` file or secret
ever lands in the repository. Two defines are supported:

| Define | Default | Purpose |
|---|---|---|
| `API_BASE_URL` | `http://10.0.2.2:8080/api/v1` | Backend root |
| `ENABLE_NETWORK_LOGS` | `true` | Verbose Dio logging (always off in release) |

Start the backend first (`cd ../backend && mvn spring-boot:run -Dspring-boot.run.profiles=dev`) and
sign in with a seeded demo account: `listener@tuneflow.dev` / `Password123` (the login screen has a
"Use" button for exactly this).

### Running on a physical Android phone

`10.0.2.2` only exists inside the emulator. On a real device, forward the port over USB — no Wi-Fi
needed, no Windows Firewall rule, and it keeps working when the phone changes networks:

```bash
adb reverse tcp:8080 tcp:8080        # phone's localhost:8080 -> your PC's localhost:8080
flutter run --dart-define=API_BASE_URL=http://localhost:8080/api/v1
```

`run-android.cmd` in this folder does exactly those two steps on Windows.

Prefer the LAN instead? Start the backend on `0.0.0.0`, allow port 8080 through Windows Firewall,
and pass `--dart-define=API_BASE_URL=http://<your-pc-ip>:8080/api/v1`.

Debug builds declare `android:usesCleartextTraffic="true"` in `android/app/src/debug/AndroidManifest.xml`.
Android rejects plain-HTTP traffic from API 28 onwards, and the resulting
`CLEARTEXT communication to ... not permitted by network security policy` error is easy to misread
as "the backend is down". Release builds keep the secure default, so production must be HTTPS.

### Troubleshooting the Android build on Windows

| Symptom | Cause | Fix |
|---|---|---|
| `:shared_preferences_android:compileDebugKotlin` fails with `AssertionError: Could not close incremental caches` and `this and base files have different roots: C:\Users\...\AppData\Local\Pub\Cache\... and D:\...` | The Kotlin incremental compiler cannot express Pub-cache source paths relative to a project root on a different Windows drive | `flutter clean`, then rebuild. If it comes back, keep `kotlin.incremental=false` (already set in `android/gradle.properties`) and/or move the Pub cache onto the same drive as the project: `setx PUB_CACHE D:\pub-cache` in a fresh terminal |
| Gradle daemon: `cannot connect to registry: Connection refused`, then the in-process fallback fails the same way | Stale daemon after the project was moved/renamed | `cd android && gradlew.bat --stop`, then `flutter clean`, then retry |
| `CLEARTEXT communication ... not permitted` | Plain-HTTP base URL | Handled — the **main** manifest sets `usesCleartextTraffic` for every variant (the native audio stack honours Android's cleartext policy in release builds even though Dart's HTTP client does not, which is why a debug-only flag once made release builds upload fine but never play); use HTTPS + a network security config for production |
| AGP deprecation warnings about `android.newDsl`, `android.builtInKotlin`, `org.jetbrains.kotlin.android` | Informational only under AGP 9 | Ignore — they do not fail the build |
| `:app:compileDebugJavaWithJavac` fails with `GeneratedPluginRegistrant.java: error: cannot find symbol` / `class FilePickerPlugin`, and the Gradle log shows `:file_picker:compileDebugKotlin NO-SOURCE` | A plugin that decides whether to apply the Kotlin Gradle Plugin from the **AGP version alone**. The Flutter 3.44+ template ships `android.builtInKotlin=false` (alongside `android.newDsl=false`), so AGP 9 does not supply Kotlin, and a plugin that skips its own Kotlin plugin on AGP 9 leaves its `.kt` files uncompiled — the class the generated registrant imports is then missing | Upgrade to a package version that reads the `android.builtInKotlin` flag: `file_picker` 13.x (its Android half is `android_file_picker` ≥ 1.0.3) instead of 11.x. Diagnose it by looking for `NO-SOURCE` on a plugin's `compileDebugKotlin` when its `android/src/main/kotlin` is not empty. Changing a plugin version changes the native module set, so rebuild from a clean slate: `flutter clean`, then `cd android && gradlew.bat --stop` |

---

## Architecture

Feature-first clean architecture, exactly as the technical documentation specifies: every feature owns
its `data/`, `domain/` and `presentation/` layers, and `core/` holds infrastructure that features are
allowed to depend on but which never depends on a feature.

```
lib/
├── main.dart                     entry point: bindings, preferences override, runApp
├── app/
│   ├── app.dart                  MaterialApp.router, theming, text-scale clamp
│   ├── root_shell.dart           tab shell: content + mini-player + navigation bar
│   └── router/
│       ├── app_router.dart       GoRouter with the auth guard and the tab shell
│       └── route_paths.dart      route constants and builders
├── core/
│   ├── config/                   AppConfig (compile-time configuration)
│   ├── constants/                ApiEndpoints, AppConstants, StorageKeys
│   ├── error/                    AppException hierarchy + error translation
│   ├── network/                  ApiClient, envelope codec, interceptors, paging
│   ├── providers/                core_providers (config, storage, Dio, ApiClient)
│   ├── storage/                  secure token storage, SharedPreferences wrapper
│   ├── theme/                    colours, typography, light/dark themes
│   ├── utils/                    formatters, validators, UUID generator, logger
│   └── widgets/                  Artwork, loading/empty/error states, status pill
└── features/
    ├── auth/                     register, login, refresh, password reset, session restore
    ├── catalog/                  songs/albums/artists/genres, home feed, search
    ├── home/                     home tab (renders the server-driven feed)
    ├── search/                   search tab (genres → suggestions → results)
    ├── library/                  likes, recently played, listening stats
    ├── playlist/                 playlist CRUD, reorder, song picker sheet (search + multi-select)
    ├── player/                   the cross-feature player service + mini/full player UI
    ├── upload/                   artist song publishing: chunked/resumable audio upload + metadata
    ├── profile/                  profile, settings, notifications
    └── downloads/                download records and lifecycle
```

Each feature follows the same three layers:

```
presentation ──▶ domain ◀── data
   screens        entities     datasources  (HTTP)
   providers      repository   repositories (implementation)
   widgets        usecases
```

* **`domain`** holds entities, the repository *interfaces* and use cases. Pure Dart — no `dio`, no
  `flutter_secure_storage`, no plugins. That is what makes the domain testable without a device.
* **`data`** implements those interfaces on top of the API.
* **`presentation`** is Riverpod providers + widgets, and never touches Dio or storage directly.

### Why there is a `catalog` module

The documentation's feature list has no "catalogue" entry, but `Song` is consumed by home, search,
library, playlists, the player and downloads. Putting the shared entities in one module (mirroring the
backend's `music` module) is cleaner than seven features importing each other's models, and it keeps
the dependency graph acyclic: features depend on `catalog`, never the reverse.

---

## State management

Riverpod throughout, with one deliberate split:

* **Async state** (`AsyncNotifierProvider` / `FutureProvider`) for anything that comes from the API.
  `AsyncValue` already models loading/data/error, so screens use `.when(...)` and no provider ever
  returns a half-initialised value.
* **Synchronous state** for the two things that must be readable during a rebuild without awaiting:
  the auth session and the player.

Providers are composed rather than injected into widgets: `apiClientProvider` →
`catalogRepositoryProvider` → `homeFeedProvider` → `HomeScreen`. A screen therefore has no constructor
dependencies at all, and tests override a single provider to substitute a fake.

Selected providers:

| Provider | Type | Purpose |
|---|---|---|
| `apiClientProvider` | `Provider` | Shared Dio-backed API client |
| `authControllerProvider` | `NotifierProvider` | Session state, consumed by the router guard |
| `currentUserProvider` | `Provider` | Convenience selector for the profile |
| `homeFeedProvider` | `FutureProvider` | Home tab feed |
| `songProvider(id)` | `FutureProvider.family` | One song, refreshed after like/unlike |
| `playerControllerProvider` | `NotifierProvider` | The player service (below) |
| `likedOverridesProvider` | `StateProvider` | Optimistic like state |
| `playlistDetailProvider(id)` | `FutureProvider.family` | Playlist with its tracks |

---

## The player service

`features/player` is a cross-feature singleton with a single owner of playback:

```
PlayerController (Riverpod Notifier)
   ├── AudioEngine            ← JustAudioEngine (just_audio), behind an interface
   ├── PlaybackRepository     ← signed stream URLs + POST /history reporting
   └── PlayerState            ← idle | loading | playing | paused | completed | error
```

Design points worth calling out:

* **The audio backend is behind an interface.** `AudioEngine` exposes position/duration/buffer/state
  streams and five commands. The plugin's own enums never escape `JustAudioEngine`, so the state
  machine is unit-testable with a fake engine and a future `audio_service` migration ("background
  playback") touches one file.
* **One signed URL per track.** Signed URLs are short-lived and rotate, so the controller fetches a
  fresh URL per track and re-fetches before it expires (`streamUrlSafetyMargin`), rather than handing
  the whole queue to the plugin up front and letting tracks fail mid-song.
* **`POST /history` is reported on progress and at the end.** Every 30 s of playback sends
  `finalUpdate: false`; stopping, skipping or completing sends `finalUpdate: true`. Only the final
  update is authoritative, which is why the play counter is accurate instead of inflated. Analytics
  failures are logged and dropped — a dropped history ping must never interrupt playback.
* **Queue semantics are explicit.** Tapping a row plays it *inside the list it was tapped in*, so
  "next" means the next visible row. Shuffle reorders the upcoming tracks; repeat cycles
  off → all → one.
* **Six states, no more.** `completed` is distinct from `paused` so the UI can offer "replay" rather
  than "resume", and `error` carries a message that the mini-player and full player both render.
* **Signed URLs are resolved before they reach the plugin.** The API may answer with a root-relative
  path (`/api/v1/media/audio/…?expires=…&signature=…`) when it is not configured with a public base
  URL, and `just_audio` will not play a bare path — that was the "upload succeeds but the song never
  plays" bug. `core/utils/media_url.dart#resolveMediaUrl` turns it into an absolute URL: absolute
  `http/https/data` URLs pass through untouched (a CDN deployment costs nothing), a leading `/` is
  resolved with `Uri.resolveUri` so the query signature survives, and a bare relative path is joined
  onto the trimmed API base. A backend that signs against `localhost` while the app reaches the API
  on a LAN IP gets its host retargeted too (the signature covers key + expiry only, so the swap is
  safe) — that is the "phone on WiFi, backend on the PC" case. `Artwork` and
  `PlaybackRepositoryImpl.getStreamUrl` both use it.

---

## Networking

```
ApiClient  ──▶  ApiEnvelope.unwrap  ──▶  plain payloads, or a typed AppException
```

* **One place parses the envelope** (`{success, message, data, timestamp}` /
  `{success, message, errorCode, fieldErrors}`). Repositories receive unwrapped payloads; nothing else
  in the app knows the transport shape.
* **Every failure becomes an `AppException`**: `ApiException` (with `errorCode`, `statusCode` and
  field errors), `NetworkException` (with a `timeout` flag), `SerializationException`,
  `SessionExpiredException`, `DeviceException`. Widgets render `error.message` and never inspect a
  `DioException`.
* **`PagedResponse<T>`** mirrors the server's pagination envelope, so pagination is parsed once.
* **Interceptors**, in order:
  1. `AuthInterceptor` — attaches the bearer token, and on a `401` performs a **single-flight refresh**
     and replays the original request. Single-flight matters: refresh tokens rotate, so ten concurrent
     401s firing ten refreshes would invalidate the session (`INVALID_REFRESH_TOKEN`). The refresh call
     goes through a bare Dio instance, so a failed refresh can never recurse.
  2. `RetryInterceptor` — retries **GETs only** with exponential backoff plus jitter, honouring
     `Retry-After` on `429`. Retrying a POST could double-like or double-download.
  3. `LoggingInterceptor` — development logging that never prints `Authorization` headers or audio
     bytes, and is compiled out of release behaviour.

---

## Session and routing

* Tokens live in the platform keystore (`flutter_secure_storage`, EncryptedSharedPreferences on
  Android, Keychain on iOS) with an in-memory mirror for the request path.
* A cold start restores the session by calling `/users/me`, which doubles as validation because the
  interceptor silently rotates an expired access token. **Offline cold start** falls back to the cached
  profile so the app opens instead of showing a login screen for a user who is still signed in.
* A rejected refresh clears credentials and emits `SessionEvent.expired`; the auth controller flips to
  `unauthenticated` and the router redirects.
* Routing (`GoRouter`) uses a `StatefulShellRoute.indexedStack`, so each tab keeps its own navigation
  stack and scroll position. The splash screen is held until the auth status resolves (`unknown`), which
  is what stops the login form flashing for returning users.

Two invariants in `app_router.dart` are easy to break and impossible for `flutter analyze` to catch.
Both shipped broken once, so `test/app/router_test.dart` now asserts them by building the real router:

1. **Every `parentNavigatorKey` must resolve.** The full-screen routes (player, settings,
   notifications, downloads, and the catalogue detail screens) declare `parentNavigatorKey` so they
   open *above* the tab shell. go_router asserts that such a key is either an ancestor `ShellRoute`'s
   key or the key passed to `GoRouter(navigatorKey: ...)`; when it is neither, the app dies on the
   first route parse with `'allowedKeys.contains(parentKey)'` — a red screen at launch, not a warning.
   The key is therefore created *inside* `routerProvider` and handed to both.
2. **Every `RoutePaths` builder must point at a route that exists.** The detail screens live at the
   top level (`/album/:id`), matching the builders, so a link can never land on the "Not found" page.
   The test walks the whole table and fails if the error screen appears.

Being root-level, the detail screens cover the tab bar and the mini-player while open. That is a
deliberate trade-off: the alternative is nesting them under `/home`, which makes a playlist opened
from the Library tab silently switch the visible tab. Moving them is a one-line change per route if
the tab bar should stay visible.

| Route | Screen |
|---|---|
| `/` | Splash (session restore) |
| `/login`, `/register`, `/forgot-password` | Auth |
| `/home`, `/search`, `/library`, `/profile` | The four tabs |
| `/album/:id`, `/artist/:id`, `/playlist/:id`, `/genre/:id` | Detail screens (root-level, above the shell) |
| `/library/liked`, `/library/recent` | Liked songs, recently played |
| `/player` | Expanded player (pushed above the shell) |
| `/settings`, `/notifications`, `/downloads` | Profile-adjacent screens |

---

## Error and empty states

Three shared widgets cover every non-happy path, so no screen invents its own: `LoadingView` /
`SkeletonList`, `EmptyView` (with an optional action) and `ErrorView` (which maps any thrown object and
only offers "Try again" when `isRetryable`). Pull-to-refresh is wired on every list, including the error
state — a failed load is precisely when a user reaches for it.

---

## The two artist/playlist flows

### Adding songs to a playlist

Every playlist surface routes into the same sheet:

| Entry point | Behaviour |
|---|---|
| Playlist detail → **Add songs** (also the empty state's call to action) | Opens the picker for that playlist |
| Album detail → **Add album to playlist** | Opens the playlist chooser with *every* track of the album (the old behaviour added only the first track, which looked like a successful "add this album" until the playlist was opened) |
| Any `SongTile` → 3-dot menu → *Add to playlist* | Opens the playlist chooser for that one track |
| Library → created-playlist snackbar → *Add songs* | Straight into the picker for the playlist just created |

The sheet is a non-draggable fixed-height panel (85 % of the viewport, keyboard-aware via
`viewInsets`) because a draggable sheet cannot host pinned footer buttons: `DraggableScrollableSheet`
sizes its child through a `FractionallySizedBox` with no `widthFactor`, which hands a full-width
themed `FilledButton` an infinite width and fails layout.

Inside it:

- The query runs against `GET /songs?q=…` with a 300 ms debounce; an empty query shows the trending
  list instead, so the sheet is never blank.
- `genresProvider` supplies the genre chips, `catalogRepository` supplies the pages.
- Tracks already in the playlist arrive disabled, so an invalid add cannot be attempted.
- Adding loops `POST /playlists/{id}/songs` one song at a time, tolerates the
  `SONG_ALREADY_IN_PLAYLIST` conflict, and reports a `PlaylistAddResult` summary ("3 songs added, 1
  was already there").

### Publishing a song as an artist

`Profile → Upload a song` (visible to `ARTIST`/`ADMIN` accounts; a listener who deep-links to
`/upload` gets an explanation rather than a form that would `403`).

1. **Audio** — `file_picker` → a size/extension check on the client (mp3/m4a/aac/wav/flac/ogg,
   ≤ 100 MB) → upload with progress. The response is the `objectKey` the song will reference **and**
   the duration the server measured, which is written into the form.

   **Two upload shapes, chosen by size** (`UploadRemoteDataSource.chunkThresholdBytes`, 2 MB):

   * under the threshold — one multipart `POST /uploads/audio`;
   * at or above it — `ChunkedAudioUpload` opens a session, writes the parts the server asked for and
     completes it. `POST /uploads/audio/initiate` returns the chunk size, so the client never guesses;
     parts go up **sequentially** (parallel part-PUTs saturate a phone's uplink and make the progress
     bar lie), each with 3 attempts and a 600 ms × attempt backoff. A part that fails burns only that
     part's progress credit. If the retry budget is exhausted the session is `DELETE`d and the error is
     surfaced, so a half-uploaded track never lingers server-side.

   Resume is real: the session carries `receivedParts`, and a retry of the same file pre-credits and
   skips them. Sessions are validated against the file — if the server's `partCount` disagrees with the
   local plan, the upload aborts with a distinguishable error rather than writing a corrupt object.
   Progress is bytes-committed / total and only reaches `1.0` after `complete` succeeds.
2. **Cover** — optional, `POST /uploads/image` (jpg/png/webp ≤ 10 MB).
3. **Metadata** — title, duration (validated against the API's 1–7200 s), album (preferring the
   account's own albums, with an "Add album" path), track number, release date capped at today,
   explicit flag, genre chips from `genresProvider`.

The publish is deliberately two calls: upload first, then `POST /songs` with the returned
`audioObjectKey`. A metadata rejection therefore never re-sends a 40 MB file. On success the app
invalidates the home feed, trending, song and artist providers so the new track appears immediately,
announces it, and returns to where the artist came from.

Bytes, not paths: `MediaFile` carries `Uint8List`, so the same code path works on Android, iOS and
web — no `dart:io` in the upload feature.

---

## Testing

```bash
flutter test        # 105 tests
flutter analyze     # zero issues
```

| Suite | Covers |
|---|---|
| `test/core/validators_test.dart` | Email/password/name rules **mirroring the backend's Bean Validation** — the failure mode this prevents is a form that looks valid and still returns 400 |
| `test/core/app_exception_test.dart` | Envelope unwrapping, field errors, `401`/`429`/timeout/connection mapping, "an unknown object never escapes as a bare exception" |
| `test/features/player/player_state_test.dart` | Progress and remaining-time maths, clamping past the track end, zero-duration guard, `copyWith` clearing, repeat-mode cycle |
| `test/features/player/mini_player_test.dart` | Renders nothing when idle; play/pause reflects state; playback errors are surfaced |
| `test/features/playlist/song_picker_sheet_test.dart` | The add-songs sheet: trending list before a query, multi-select, the `POST /playlists/{id}/songs` calls it makes and their order, rows already in the playlist are unselectable, unticking clears the action |
| `test/features/upload/upload_controller_test.dart` | Upload rules end to end at the controller: size/extension rejection before any bandwidth is spent, a cancelled pick is a no-op, a failed upload leaves no file or `objectKey`, the measured duration seeds the form and an explicit edit wins, `blockingReason` guidance, and the metadata the publish call actually sends |
| `test/features/upload/upload_song_screen_test.dart` | The screen as an artist uses it: a listener gets an explanation instead of a form that would 403, the empty form cannot publish and says why, pick → upload → duration filled → title → publish reaches the API, and a regression under a real `GoRouter` that the post-publish "View artist" snackbar action navigates after the screen has popped (it used to crash on the deactivated context) |
| `test/core/media_url_test.dart` | Signed-URL resolution: absolute/CDN and `data:` URLs untouched, a leading `/` keeps its signature query, a bare relative path is joined onto the trimmed base, backend-`localhost` URLs are retargeted to the host the app actually reaches the API on (but left alone under adb-reverse `localhost`), and an empty configuration falls back safely — the fix for uploads that stored fine but never played |
| `test/features/player/resolve_playback_url_test.dart` | The engine’s last line of defence: with no API base wired the URL passes through, a relative signed URL is absolutized right before ExoPlayer, a loopback-signed URL is retargeted onto the LAN base, and an already-reachable absolute URL is left untouched |
| `test/features/playlist/playlist_dialogs_test.dart` | The playlist dialog and the change-password sheet close cleanly while a field holds focus: cancelling a focused dialog, creating a playlist end-to-end against a fake API, and submitting the password sheet all finish the exit transition with no "TextEditingController used after disposed" red screen |
| `test/features/player/player_controller_error_test.dart` | A failed native load surfaces the URL the player tried inside the error message, so "could not play" is self-diagnosing (relative / loopback / unreachable host) |
| `test/features/upload/chunked_upload_test.dart` | The chunk planner and the resume logic: part boundaries and the last-part remainder, a server chunk size smaller/larger than expected, part-count mismatch aborts the session, retry-then-succeed reports progress exactly once, an exhausted budget `DELETE`s the session and rethrows, and progress never exceeds 1 |
| `test/features/upload/upload_route_test.dart` | Which upload shape the data source picks: a 400 KB file is one multipart request with no session traffic at all, a file at the threshold opens a session, sends the parts in order and completes once, and fraction progress is monotonic ending at 1 — verified against a recording `ApiClient` |
| `test/features/player/playback_repository_test.dart` | A relative signed URL is absolute by the time the player sees it, an absolute CDN URL is passed through untouched, and the returned descriptor keeps a future expiry |
| `test/features/catalog/song_tile_test.dart` | Title/artist/duration/explicit flag, like state and overrides, now-playing highlight |
| `test/app/router_test.dart` | The router configuration itself: no dangling `parentNavigatorKey`, every buildable location resolves to a real screen (not the "Not found" page), the auth guard still redirects signed-out users, and the player opens above the shell rather than inside it |

Widget tests override a single provider (a fake `PlayerController`) rather than mocking the world,
which is the practical payoff of keeping providers composable.

---

## Deliberate decisions and known gaps

| Decision | Rationale |
|---|---|
| **Hand-written JSON parsing** (no `freezed`/`json_serializable`) | Removes a build_runner step from the loop, and the parsing is genuinely defensive: the API omits null fields, so every accessor tolerates a missing key. Worth revisiting if the model count triples. |
| **`just_audio`, no `audio_service`** | Background playback needs native service configuration on both platforms. The `AudioEngine` seam is where it plugs in, and the player logic is already independent of it. |
| **Downloads record state, they do not write files** | The API models a download as a licence with a `PENDING → COMPLETED` lifecycle. Writing bytes to disk is a separate concern (workmanager + a local file store) and is called out as the next step rather than faked. |
| **Stream URLs are never cached for playback** | They expire, so caching a URL is a latent bug that surfaces as "some tracks just stop working". |
| **No admin UI** | Out of scope by decision (no admin REST API either). The **artist** upload UI does exist — see [the two flows](#the-two-artistplaylist-flows). |
| **`file_picker` 13 and `flutter_secure_storage` 11 are deliberately paired** | `file_picker` 13's Android implementation reads the `android.builtInKotlin` flag (the 11.x one only looked at the AGP version and broke the build), and it pulls `windows_file_picker`, which needs `win32` 6.x — which the Windows half of `flutter_secure_storage` 9.x cannot use. Bumping the two together is the only combination that resolves *and* builds. `flutter_secure_storage` 11 also removed the `encryptedSharedPreferences` option (`TokenStorage` no longer passes it); the default is AES-GCM with RSA-OAEP key wrapping. |
| **Notifications use the existing providers, not a new module** | One consumer today; if a second appears, the providers move without touching screens. |
