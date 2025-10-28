# Lightweight Console - Developer Notes

## Current State (2025-10-27)

- Menubar app target (`Lightweight Console`) built for macOS 15.6.  
- Uses `CreatureServerClient` from Common (shared package) with REST + websocket.  
- Preferences stored in `UserDefaults`; API key kept in `lightweight.proxyApiKey`.
- Key actors: `LightweightClientController` (server bridge), `LightweightClientViewModel` (UI state), `LightweightMessageProcessor` (websocket filtering).
- Streaming caches: `LightweightHealthStore` and `LightweightJobStore` maintain latest board sensor + job status without SwiftData.
- Prepared animations auto-refresh when ad-hoc prepare job completes.
- UI trims prepared list to 5 items by default; show-all toggle available.  
  Playlists launch via single `Menu("Start Playlist")` + stop button.

## Outstanding / TODO

- UITests (`Lightweight_ClientUITests.testExample`) are obsolete; update or replace with Swift Testing coverage on view model.
- Health section only surfaces motor-in metrics; extend if more signals needed.
- Consider confirming destructive actions (stop playlist) with a sheet.
- The controller still bootstraps the websocket even if REST setup fails—could surface failure handling.
- Creature dropdown fetch happens on websocket connect; watching for `WebSocketStateManager` only.  Potentially move to explicit refresh or REST ping on save.

## Gotchas

- `CODE_SIGNING_ALLOWED=NO` required for headless builds/tests in CLI (otherwise codesign failure).  
- Default values registered through `lightweightDefaultValues`; make sure to add new keys there.
- When adjusting UI width, keep to 360pt to avoid cramped menubar popover.
- Connection header expects `viewModel.creatures` to hold the selected ID; ensure refresh runs before drawing personalized placeholder.

## Quick Commands

```bash
# format targeted files
swift-format --configuration swift-format.json --in-place Lightweight\ Console/... 

# build without codesign
xcodebuild build -scheme "Lightweight Console" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO

# run tests (UI tests still flaky until updated)
xcodebuild test -scheme "Lightweight Console" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO
```

