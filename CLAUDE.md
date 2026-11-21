# CLAUDE.md

iOS app that searches GitHub repositories via the [Search repositories API](https://docs.github.com/en/rest/search/search#search-repositories) and lists the results with each owner's avatar.

## Build

- Xcode project: `SwiftUISampleApp/SwiftUISampleApp.xcodeproj`. Its shared scheme `SwiftUISampleApp` builds the app and runs both test targets. No Swift packages.
- Build from the repo root:
  ```sh
  xcodebuild -project SwiftUISampleApp/SwiftUISampleApp.xcodeproj -scheme SwiftUISampleApp -destination 'generic/platform=iOS Simulator' build
  ```
  A successful build prints `BUILD SUCCEEDED` with no Swift warnings. The `appintentsmetadataprocessor ... no AppIntents.framework dependency` warning is expected and harmless.
- Language mode: **Swift 6** (`SWIFT_VERSION = 6.0`), so strict concurrency checking is on. Deployment target iOS 17.0, iPhone and iPad.
- Editor SourceKit errors such as "No such module 'UIKit'" or "Cannot find 'Repo' in scope" come from the VS Code `buildServer.json` setup, not the real build. Trust `xcodebuild`.

## Tests

- `SwiftUISampleAppTests`: unit tests written with Swift Testing (`import Testing`, `@Test`, `#expect`). They cover `NetworkManager` (search and image cache), `RepoViewModel`, `AvatarViewModel`, the models, `UITestStubURLProtocol`, and smoke-render the views.
  - The tests never touch the network: `StubURLProtocol` answers each URL with a canned response and counts requests.
  - Each test uses unique URLs/keywords and its own cache directory, created with `NetworkManager(session:imageCacheDirectory:)`, so tests can run in parallel.
  - To call the synchronous `RepoViewModel.getRepos(keyword:)` from an async test, go through a non-async helper; otherwise the compiler picks the async overload.
- `SwiftUISampleAppUITests`: XCUITest end-to-end tests. They launch the app with `-UITestStubNetwork`, so every request is answered by `Network/UITestStubURLProtocol.swift` (compiled only in Debug). No network is needed. In this mode `NetworkManager.makeShared` uses a separate avatar cache, `tmp/UITestImageCache/`, which is emptied at every launch, so runs don't depend on earlier runs.
  - Search keywords with special responses: `error` (HTTP 500), `empty` (no results), `slow` (1.5s delay, shows the spinner), `shared-owner` (all rows share one avatar), `broken-avatar` (avatars return 404). Any other keyword returns 10 repos named `stub/<keyword>-<n>`.
  - They find avatars by accessibility identifier: `avatar.loaded` or `avatar.placeholder`, set in `RepoRow.swift`.
- Run them (use a standard iPhone simulator; the test runner hung on the "iPhone Duo" simulator):
  ```sh
  xcodebuild test -project SwiftUISampleApp/SwiftUISampleApp.xcodeproj -scheme SwiftUISampleApp \
    -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:SwiftUISampleAppTests \
    -resultBundlePath build/UnitTests.xcresult   # or SwiftUISampleAppUITests / build/UITests.xcresult
  ```
- Coverage: the scheme collects coverage for the app target only. Each suite on its own must keep **at least 80%** line coverage of the `SwiftUISampleApp.app` target. Check it with `scripts/check-coverage.sh <bundle>.xcresult 80`, which prints a per-file report and exits non-zero below the threshold. When you add code, add tests to both suites as needed rather than lowering the threshold.
- Make new code testable by injecting dependencies with production defaults, e.g. `AvatarViewModel(networkManager: .shared)`.

## CI

`.github/workflows/ci.yml` (GitHub Actions, `macos-26`, latest stable Xcode) runs on pushes to `develop`/`main`, on pull requests, and on manual dispatch. It has two parallel jobs:
- `unit-tests`: a Release simulator build with `CODE_SIGNING_ALLOWED=NO` (this proves the Debug-only stub compiles out), then the unit tests and the 80% coverage gate.
- `ui-tests`: the UI tests and the 80% coverage gate.

Each job uploads its `.xcresult` and coverage report as artifacts, and writes a coverage table to the job summary. `scripts/pick-simulator.sh` picks the simulator, because runner images ship different device names.

## Adding files

The project does **not** use synchronized folders (`objectVersion = 56`). A new `.swift` file must be registered in `project.pbxproj` by hand, or it won't compile. Add four entries, copying an existing file's entries as a pattern (e.g. `RepoViewModel.swift`):
1. `PBXBuildFile`
2. `PBXFileReference`
3. a child in the right `PBXGroup`
4. an entry in that target's `PBXSourcesBuildPhase` (app, unit test or UI test target)

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
  - `makeShared(arguments:)` builds `shared`, and `makeDefaultSession(arguments:)` builds its `URLSession`. In Debug builds, the `-UITestStubNetwork` launch argument switches the session to `UITestStubURLProtocol`, which answers every request. It also switches the image cache to `tmp/UITestImageCache/`, which is emptied at launch. Release builds always use a plain default session and `tmp/ImageCache/`.
  - `loadImageData(url:)` and `download(url:toFile:)` handle images. They cache files in `tmp/ImageCache/`, named by a SHA-256 hash of the full URL and moved into place in one step. A cached file is reused for 24 hours. After that it's re-downloaded, but the old copy is still shown if the download fails (e.g. offline). `pruneImageCache()` runs in the background at launch (`AppDelegate`) and deletes files older than 7 days.

## Conventions

- Views never call `NetworkManager` directly. Network calls go through a view model.
- Give each view model state with its own lifetime. Screen state belongs in `RepoViewModel`. Per-row state belongs in a row-level view model, so that publishing it doesn't redraw the whole list. Don't fold avatar loading into `RepoViewModel`.
- View models are `@MainActor final class ...: ObservableObject` with `@Published` properties. Views own them with `@StateObject`.
- Use async/await rather than completion handlers. Start async work from views with `.task` / `.task(id:)` so it's cancelled automatically, and check `Task.isCancelled` before publishing results.
- Types shared across actors must be `Sendable` (e.g. `NetworkManager` is a `final class ... : Sendable`). Don't silence concurrency diagnostics with `@unchecked Sendable` or `nonisolated(unsafe)` unless you can explain why it's safe.
- Keep slow work off the main actor: disk reads, network calls and image decoding. For example, decode images with `UIImage.byPreparingThumbnail(ofSize:)`.
