# Creature TV: Spatial Audition over HDMI

Tracking issue: [#70](https://github.com/opsnlops/creature-console/issues/70). Phase 1: audition only.

## Why the Apple TV

April's living room: Apple TV → HDMI → Denon receiver. App-generated audio over AirPlay is a
stereo pipe (Atmos passthrough is reserved for Apple's encoded streams), so a Mac auditioning
spatially into that room folds the mix down before it arrives. The same engine **running on the
Apple TV** emits discrete multichannel LPCM (5.1/7.1) over HDMI — real channels, receiver doing
honest work. This is the standard tvOS game-audio path.

## Architecture: widen, don't fork

The spatial stack is engine-based, portable code behind `#if os(macOS)` fences. The plan is to
widen the fences on the audition chain to `#if os(macOS) || os(tvOS)` and attach the
`SpatialAudio` synchronized folder to the TV target — not to copy anything.

**Widened** (the audition chain):
`SpatialStageTypes` (diagnostics/level types) → `SpatialPCMQueue` → `SpatialAudioRenderer` →
`SpatialSimulationAudioSource` → `SpatialSimulationCache` → `SpatialAuditionPlayer` →
`LocalAudioPlayer` (internal fences).

**Stays macOS-only**: the live RTP path (`SpatialLiveAudioSource`, `SpatialMulticastReceiver`,
`SpatialOpusDecoder` — show monitoring, not audition), the stage editor surfaces
(`SpatialStageView`/`ViewModel`/`Scene`), and the UserDefaults legacy migration.

**Already TV-side** (dividends of earlier work): `AudioManager` (dual-registered),
`StageModel`/`StageImporter` + `DialogScriptModel` + `AnimationMetadataModel` mirrors fed by
cache invalidation, and all of Common's URL/rendition machinery.

## tvOS audio session

`AVAudioSession` category `.playback`, `preferredOutputNumberOfChannels =
min(maximumOutputNumberOfChannels, 8)`, configured at spatial-play time (tvOS only; macOS has no
session). The environment node renders to the negotiated layout; a stereo route degrades
gracefully — same mix, fewer speakers. Receiver-side: ATV Audio Format should be Auto/LPCM;
document, don't fight it.

## TV surface (lean)

`TVSpatialAuditionView` in `Creature TV/`:
- **Dialogs**: scripts whose `acceptedVoice` has a promoted `sound_file` *and* a bound stage →
  play the accepted voice on that stage.
- **Animations**: rendered animations with a `sound_file` and a `source_stage_id` that resolves
  in the stage mirror → play the render's 17ch WAV on its source stage.
- Tap to play through `LocalAudioPlayer.playSpatially`; now-playing banner; play again to
  restart, dedicated stop. No editing from the couch — this is ears only.

Sidebar entry in `TopContentView`'s tvOS section.

## Out of scope (phase 1)

Couch editing, live RTP monitoring, per-take candidate browsing (accepted voices only — the TV
plays what was *chosen*), and anything labelled Atmos: discrete LPCM is the honest ceiling.
