# CLAUDE.md

iOS app that searches GitHub repositories via the [Search repositories API](https://docs.github.com/en/rest/search/search#search-repositories) and lists the results with each owner's avatar.

## Build

- Xcode project: `SwiftUISampleApp/SwiftUISampleApp.xcodeproj`, single app target and scheme `SwiftUISampleApp`. No test target, no Swift packages.
- Build from the repo root:
  ```sh
  xcodebuild -project SwiftUISampleApp/SwiftUISampleApp.xcodeproj -scheme SwiftUISampleApp -destination 'generic/platform=iOS Simulator' build
  ```
  A successful build prints `BUILD SUCCEEDED` with no Swift warnings. The `appintentsmetadataprocessor ... no AppIntents.framework dependency` warning is expected and harmless.
- Language mode: **Swift 6** (`SWIFT_VERSION = 6.0`), so strict concurrency checking is on. Deployment target iOS 17.0, iPhone and iPad.
- Editor SourceKit errors such as "No such module 'UIKit'" or "Cannot find 'Repo' in scope" come from the VS Code `buildServer.json` setup, not the real build. Trust `xcodebuild`.

## Adding files

The project does **not** use synchronized folders (`objectVersion = 56`). A new `.swift` file must be registered in `project.pbxproj` by hand, or it won't compile. Add four entries, copying an existing file's entries as a pattern (e.g. `RepoViewModel.swift`):
1. `PBXBuildFile`
2. `PBXFileReference`
3. a child in the right `PBXGroup`
4. an entry in the target's `PBXSourcesBuildPhase`

Use new unique 24-hex-digit IDs, then build to confirm.

## Architecture

UIKit shell hosting SwiftUI, with MVVM:

- `AppDelegate` / `SceneDelegate` / `Main.storyboard` launch `ViewController`, which embeds `RepoView` in a `UIHostingController`.
- `Repo/View/RepoView.swift` is the search screen. It owns `RepoViewModel`.
- `Repo/View/RepoRow.swift` is one result row. Its private `AvatarView` owns an `AvatarViewModel`.
- `Repo/ViewModel/RepoViewModel.swift` holds the screen's state: keyword, results, loading flag and error message.
- `Repo/ViewModel/AvatarViewModel.swift` holds one row's avatar image, which it loads, decodes and caches.
- `Repo/Model/` contains `Codable` structs (`RepoContainer`, `Repo`, `Owner`, `License`). Property names match the API's JSON keys (snake_case, e.g. `full_name`, `avatar_url`), and every field is optional.
- `Network/NetworkManager.swift` is the only place that talks to the network. Access it through `NetworkManager.shared`, a single shared instance.
  - `getData(queryParams:)` runs the repo search.
  - `loadImageData(url:)` and `download(url:toFile:)` handle images. They cache files in `tmp/ImageCache/`, named by a SHA-256 hash of the full URL and moved into place in one step. A cached file is reused for 24 hours. After that it's re-downloaded, but the old copy is still shown if the download fails (e.g. offline). `pruneImageCache()` runs in the background at launch (`AppDelegate`) and deletes files older than 7 days.

## Conventions

- Views never call `NetworkManager` directly. Network calls go through a view model.
- Give each view model state with its own lifetime. Screen state belongs in `RepoViewModel`. Per-row state belongs in a row-level view model, so that publishing it doesn't redraw the whole list. Don't fold avatar loading into `RepoViewModel`.
- View models are `@MainActor final class ...: ObservableObject` with `@Published` properties. Views own them with `@StateObject`.
- Use async/await rather than completion handlers. Start async work from views with `.task` / `.task(id:)` so it's cancelled automatically, and check `Task.isCancelled` before publishing results.
- Types shared across actors must be `Sendable` (e.g. `NetworkManager` is a `final class ... : Sendable`). Don't silence concurrency diagnostics with `@unchecked Sendable` or `nonisolated(unsafe)` unless you can explain why it's safe.
- Keep slow work off the main actor: disk reads, network calls and image decoding. For example, decode images with `UIImage.byPreparingThumbnail(ofSize:)`.
