# Async All The Things — Client Plan (issue #11)

Server 3.23.0 (creature-server#42) turns the three synchronous ElevenLabs endpoints into
jobs. Client adopts them everywhere.

## Common package

- `JobType` gains `.dialogPreview` (`"dialog-preview"`), `.dialogPreviewExport`
  (`"dialog-preview-export"`), `.voiceFile` (`"voice-file"`).
- `dialogPreviewMeta` returns `DialogPreviewMetaOutcome` — `.meta(DialogPreviewMetaDTO)`
  on 200, `.queued(JobCreatedResponse)` on 202 (status-code switch on
  `sendDataResponse`).
- `dialogPreviewMultichannel` returns `.queued(JobCreatedResponse)` (always async now);
  the job result's `file_name` is downloaded via the existing ad-hoc sound URL.
- `createCreatureSpeechSoundFile` returns `JobCreatedResponse`.
- New `getJob(jobId:)` REST method for the CLI's polling (`GET /api/v1/job/{jobId}`).

## App

- `DialogPreviewPanel` gets one `resolveMeta(request)` helper: sync meta passes through;
  `.queued` seeds the store (`seedQueued`) and consumes
  `JobStatusStore.events(forJob:)` — the shared stream from the DRY pass — surfacing
  progress in `statusMessage` ("Generating voices… 40%"), then decodes the meta DTO from
  the terminal result. Preview + mono export + shareable-ogg export all route through it.
- The 17-channel export watches its `dialogPreviewExport` job, then downloads the
  resulting file from the ad-hoc bucket.
- `CreateNewCreatureSoundView` (POST /voice) watches its `voiceFile` job the same way.

## CLI

- Export/preview/voice commands poll `getJob(jobId:)` (1s interval, generous deadline)
  when they receive `.queued`, printing progress, then proceed as before.

## Versioning

Folds into the unreleased 2.30.0 (this feature set has not shipped; no extra bump).
