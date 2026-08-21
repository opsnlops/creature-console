# Streamed Ad-Hoc Exchange Console Plan (issues #80, #81)

Console-side companion to creature-server#150 (branch `agent/150-exchange-export`),
which makes each streaming ad-hoc session a first-class "exchange" resource:
everything Beaky said in one creature-agent-driven turn, stitched into a single
fully-tagged file. GUI issue: #80 (right-click → Save MP3). CLI issue: #81
(`exchanges list/show/download`).

## Server contract (verified against the server branch)

```
GET api/v1/animation/ad-hoc-stream/exchanges                        → { count, items } newest first
GET api/v1/animation/ad-hoc-stream/exchange/{sessionId}             → one AdHocExchangeDto
GET api/v1/animation/ad-hoc-stream/exchange/{sessionId}/audio.mp3   → stitched, ID3-tagged MP3
GET api/v1/animation/ad-hoc-stream/exchange/{sessionId}/audio.ogg   → Ogg/Opus rendition
GET api/v1/animation/ad-hoc-stream/exchange/{sessionId}/audio.wav   → stitched 17-ch WAV
```

`AdHocExchangeDto` fields: `session_id`, `creature_id`, `creature_name`,
`status` (`streaming | ready | partial | failed`), `title`, `transcript`,
`duration_ms`, `created_at` (ISO8601), `finished_at` (ISO8601, absent while
streaming), `parts[{ index, animation_id, text, duration_ms }]`. The list and
detail routes return the same shape (list items include parts).

Serving semantics: `Content-Disposition` carries a friendly filename
(`Beaky - 2026-08-20 - <slug>.mp3`); `Cache-Control: public, immutable` once
ready; `409` + `Retry-After` while `streaming`; `404` for unknown sessions.
New WebSocket invalidation `cache_type: "ad-hoc-exchange-list"` fires on
create/finalize. Exchanges share the ad-hoc TTL (~12 h), so the list is
naturally "recent."

Session ids stay `String` (matching `StreamingAdHocDTO`): the server compares
them as strings in Mongo, and round-tripping through `UUID` would uppercase
them.

## Common package

- **`Model/Exchange/AdHocExchange.swift`** — `AdHocExchange` +
  `AdHocExchangePart` (`Codable, Equatable, Sendable, Identifiable`,
  `id = sessionId`) and `ExchangeStatus: String` enum with a **lenient decode**
  (unknown wire strings → `.unknown`) since the server treats status as an
  open set of labels. Hand-rolled date decoding via `ISO8601DateFormatter`
  with `.withFractionalSeconds` (same reason as `AdHocSoundEntry`).
- **`Model/Exchange/ExchangeAudioFormat.swift`** — `enum ExchangeAudioFormat:
  String, Sendable, CaseIterable { case mp3, ogg, wav }` with `fileExtension`
  and the route filename (`audio.mp3` …). `SoundRendition` is not reused: its
  `pathSegment`s encode sound-route quirks and it has no `wav` case.
- **`Model/DTO/AdHocExchangeListDTO.swift`** — `{ count, items }`.
- **`Controller/Server/RESTful/ExchangeMethods.swift`** — plain
  `extension CreatureServerClient`:
  - `listAdHocExchanges() async → Result<[AdHocExchange], ServerError>`
  - `getAdHocExchange(sessionId:) async → Result<AdHocExchange, ServerError>`
  - `getExchangeAudioURL(sessionId:format:) → Result<URL, ServerError>`
  - `downloadExchangeAudio(sessionId:format:) async →
    Result<ShareableSound, ServerError>` — mirrors `downloadSoundRendition`:
    `.useProtocolCachePolicy` (immutable once ready) and Content-Disposition
    parsed for the suggested filename, falling back to
    `<session_id>.<ext>`. The 409-while-streaming maps to the existing
    `.conflict` case with the server's message — no client retry loop.
  - `parseFilenameFromContentDisposition` is promoted from `private` to
    internal in `SoundMethods.swift` and shared (DRY).
- **`Model/CacheInvalidation/CacheInvalidation.swift`** — add
  `case adHocExchangeList = "ad-hoc-exchange-list"` **and a lenient
  `init(from:)` on `CacheType`** coalescing unrecognized strings to
  `.unknown` (today an unknown `cache_type` throws, so every future
  server-side cache type breaks old consoles' decode path).

## CLI (issue #81)

`Common/Sources/CreatureCLI/exchangesCommand.swift`, registered in `top.swift`:

```
creature-cli exchanges list                      # id, creature, age, status, duration, transcript preview
creature-cli exchanges show <session-id>         # full transcript + parts table
creature-cli exchanges download <session-id> [--format mp3|ogg|wav] [-o path] [--overwrite]
```

Follows the `soundsCommand.swift` conventions: narrow capability protocols +
`typealias ExchangeCommandClient`, injectable server-factory actor,
`tracedRun`, `printTable`, `ServerError.detailedMessage` in every failure arm.
`download` uses the in-memory `downloadExchangeAudio` (exchanges are short—
seconds to a couple of minutes) so the server's Content-Disposition filename
is honored when `-o` is omitted or is a directory; `--overwrite` gates
clobbering, exactly like `sounds share`. A `409` reports "still streaming —
try again once the session finishes" and exits non-zero without retrying.
`ExchangeAudioFormat` gets `ExpressibleByArgument` in the CLI module.

Tests in `Common/Tests/CommonTests/ExchangesCommandTests.swift` mirror
`SoundsCommandTests`: stub server actor, injected factory, download handler
stub, overwrite-refusal and conflict cases.

## GUI (issue #80)

- **`Sources/Creature Console/View/LiveMagic/AdHocExchangeViews.swift`** —
  `AdHocExchangeListView` modeled on `AdHocSoundListView` (regime B: plain
  `@State` list, `.task` initial load, `.refreshable`, toolbar refresh,
  `ContentUnavailableView` when empty, newest first). Rows show creature,
  relative time (`adHocRelativeString`), duration, transcript preview, and a
  status badge (`Label` + per-status `symbolName`/`tint`, the
  `JobStatus`-in-`LiveMagicView` pattern; `partial` gets a visible badge but
  audio stays downloadable).
- **Context menu** — the exchange share path *is* the existing "generate
  shareable version of this file" path, not a parallel one. The old
  `ShareableSoundFlow` is generalized into `ShareableAudioFlow<Request>`
  driven by a small `ShareableAudioRequest` protocol (contentType + how to
  download); `shareableSoundFlow(fileName:)` keeps its API as a thin wrapper,
  and `ExchangeShareRequest` (`sessionId` + `ExchangeAudioFormat`) is the
  exchange conformance. Menu items are `ShareableAudioButton`s with the same
  icon and the same headline title — **Generate Shareable Version…** (MP3),
  plus "Generate Ogg/Opus Version…" and "Download Stitched WAV…" — disabled
  while `streaming`, plus Copy Session ID / Copy Transcript. The flow lives
  on the `List` (stable-ancestor rule) and presents `.fileExporter` with
  `AudioFileDocument` and the matching `UTType`. tvOS branch collapses to a
  no-op (`AudioFileDocument` is Console-target-only), same shape as before.
- **Navigation** — fourth `NavigationLink` in `TopContentView`'s
  "Live Magic" section.
- **Live refresh** — `CacheInvalidationProcessor.process` gets a
  `.adHocExchangeList` case that posts a typed `NotificationCenter`
  notification; the list view listens and reloads. (Exchanges are TTL'd
  server data, not a SwiftData mirror — same regime as the other ad-hoc
  lists, but actually wired instead of "handler pending.")
- **pbxproj** — register the new view file in both the Console and TV
  targets (LiveMagic files are in both; the TV build must keep compiling).

## Release chores

- `swift-format` on every touched file; `cd Common && swift test`; macOS
  `xcodebuild test`.
- Version bump (feature ⇒ minor) to **2.52.0** in `MARKETING_VERSION`, and
  `top.swift` for creature-cli, creature-mqtt, creature-agent (lockstep).
- New `debian/changelog` entry; verify the three packaged products build in
  the `swift:6.3` Linux container before tagging.
- Branch + PR with `Fixes #80` / `Fixes #81`; tag `v2.52.0` once on `main`.
