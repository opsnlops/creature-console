# Shareable Sounds — Console Implementation Plan (issue #9)

"Generate Shareable Version…" wherever sounds appear: downloads an Ogg/Opus rendition
from the server (creature-server#36: `GET /api/v1/sound/shareable/{filename}`, searches
both the permanent and ad-hoc sound stores, downmixes multi-channel to mono, 96 kbps
Opus @48 kHz) and prompts to save it to disk.

## Common package

`SoundMethods.swift`: `downloadShareableSound(fileName:) async -> Result<(data: Data, suggestedFilename: String), ServerError>`
— URL-encodes the name, fetches via `fetchDataResponse`, reads the server's
`Content-Disposition` filename with the existing `parseFilenameFromContentDisposition`
(fallback: `<basename>.ogg`).

## Save-to-disk plumbing (shared, DRY)

- Generalize `WavFileDocument` into `AudioFileDocument` (parameterized `UTType` + data);
  `WavFileDocument` becomes a typealias/thin wrapper so DialogPreviewPanel keeps working.
- Define `UTType.oggAudio` (`UTType(filenameExtension: "ogg", conformingTo: .audio)`) —
  no Ogg UTType exists in the SDK or the app today.
- One reusable `ShareableSoundButton(fileName:)` view (in `View/Sounds/`) owning the
  whole flow: button/menu-item label → download → `.fileExporter` → error alert. The
  four call sites just instantiate it — no per-view copies of the export-state triad.

## Where the button goes (all `#if os(iOS) || os(macOS)`; tvOS has no save-to-disk story)

1. **SoundFileListView** — context menu (with the existing `.wav`-suffix gating), using
   `sound.id` as the file name. Primary surface.
2. **AdHocSoundRow** (AdHocAssetsView) — context menu, using `entry.sound.fileName`.
3. **AnimationTable** — context menu, gated on `hasSound`, using `md.soundFile`.
   (Replaces sitting next to the stubbed "Play Sound File" button.)
4. **DialogRenderPanel completion card** — dialog previews are turns-keyed, not
   file-keyed, so the dialog surface is the *render result*: the completion card knows
   `result.animationId`; fetch the animation, take `metadata.soundFile`, share that.
   Works for both ad-hoc and permanent renders since the endpoint searches both stores.

## Versioning

Bump marketing version + CLI version together before committing, per repo convention.
