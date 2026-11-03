# Voice cues: the birds perform emotion (#270) — built: agent 2.106.0, World 0.66.0, Viewer 0.24.0

Creature Server now voices ad-hoc speech and scene lines on `eleven_v4_turbo` through ElevenLabs'
text-to-dialogue socket. That model **performs** an inline audio tag rather than reading it aloud.
`I don't believe it. [sighs] Fine, we'll try again.` comes out as a real sigh. The server passes a
tagged line through as written, and keeps the mouth at rest through the tag:

- creature-server#248, #249, #253: 3.51.7
- the measurements are on #270: 47 tags rendered on Beaky's voice, none pronounced

Today the birds can't use any of this, because every path removes or forbids a bracket:

- All four personas say never to "describe actions or narrate, no 'giggles'", and every contract
  says "Do not describe actions".
- `CharacterMind.withoutStageDirections` removes every `[…]`.

This slice gives the minds a voice cue: one per line, aloud only.

## Decisions

Recommended on #270, and taken as recommended; each one is easy to change.

1. **The voice gets the cue; the record keeps the words.** The conversation keeps the plain words:
   the Communicator, the transcripts the minds read back, the memory job, the librarian and
   search all see the line without its cue. A cue in the transcript would teach every bird to copy
   it, the same leak #154 fixed for speaker labels. The line *as performed*, cue included, is kept
   beside the words as `performed`, and the Viewer shows it. Done means viewable.
2. **What a bird may say.** Name a few performed sounds (`[laughs]`, `[sighs]`, `[gasps]`,
   `[clears throat]`). Otherwise let the bird describe a feeling in its own words; Beaky's
   `[choked up with happiness]` measurably did more than `[cheerful]`. The model judges when; no
   code decides which feeling a line has.
3. **At most one cue per line, enforced in code.** Each cue costs 0.1–1.5 s of voice before the
   bird finishes speaking, on the latency the birds are judged by. The model chooses whether a line
   gets one; code only keeps the second from being performed.

The Communicator route is text, not voice. Its contract says nothing about cues, and its replies
are still stripped of every bracket.

## What counts as a cue

`WorldCore.VoiceCues` is the one definition, shared by the agent and the World:

- **A cue** is square brackets around 1–40 characters, with at least one letter, no colon, and no
  nested bracket, and is not `[silence]`.
- **Not cues:** the minds' protocol tags all carry a colon (`[learned: …]`, `[house: …]`,
  `[quiet: …]`, `[pass: …]`), and `[silence]` is the silence token. Those are handled before
  cues, as now. A longer bracket is narration and is stripped, as now.
- **The words** of a line are the line with its cues removed, whitespace collapsed, and no space
  left before punctuation (`"Fine [sighs]."` → `"Fine."`).

## The agent (creature-agent 2.106.0)

- **Contracts.** The room contract (`.physicalSpeech`), the scene contract and the house-remark
  contract each gain one passage, `CharacterMind.voiceCues`. It describes the cue, gives the
  sounds and an example feeling, and says it is the one exception to describing actions: most
  lines need none, and each one takes the voice a moment. The Communicator contract is unchanged.
  The persona files are not touched.
- **Streaming, one rule for both spoken paths.** This covers a solo reply in the room
  (`SpokenSentences`) and a streamed scene line (`StreamedLine`).
  - Narration in `*…*`, `(…)` and long brackets is stripped; a cue survives.
  - A `CueAllowance` in each actor admits the line's first cue, and drops any later ones.
  - A sentence that is only a cue waits and goes out at the head of the next sentence: the server
    refuses a cue-only chunk. A cue at the very end of a line is dropped.
  - The room path did not strip `*giggles*` or `(chuckles)` before; it does now, as the scene path
    always has.
- **Whole-line paths unchanged.** The Communicator reply and a non-streamed scene line go through
  `validate`, which still strips every bracket.
- **The intent.** A room reply's intent carries `text` (the words) and `performed` (the sentences
  as spoken), the latter only when it differs from the words.

## The World (creature-world 0.66.0)

- **Contracts.** `CharacterUtteranceIntent`, `ConversationItem` and `SceneTurn` gain an optional
  `performed`: the line as the voice performed it, cues and all. It is absent when the line had
  none, and old documents decode as before.
- **Scenes.** A piece arrives as performed.
  - The performer and the `scene.turn_piece` event get it as is. The floor keeps performed pieces.
  - When the line is taken, its `text` is the words and `performed` is the joined line.
  - The conversation item gets both. A line whose words are empty is a pass.
  - The replay check compares the submission with the performed line.
  - Both performers (streaming, and the whole scene at close) voice `performed ?? text`.
- **A room reply** becomes a conversation item with the intent's `performed`.
- **Pacing.** `spokenSeconds` counts a line's *words* at the voice's pace, plus `cue_seconds`
  (default 0.75) for each cue.
  - Before this, a cue's letters counted as speech, which is wrong in both directions:
    `[choked up with happiness]` is 26 characters and adds about 0.5 s, while `[yawns]` is
    8 characters and adds about 1.5 s.
  - The measured mean across the 47 tags is about 0.6 s, with the performed sounds higher.

## The Viewer

A bird's line shows as performed: the cue in italics, set apart from the words. This applies in
Conversation and in Scenes. The timeline's `scene.turn_piece` events carry the performed piece
already.

## Not in this slice

- Changing the personas. If the birds rarely use a cue because a persona says "no giggles", soften
  that line then. One change at a time.
- A cue on a Communicator reply, as a written stage direction.
- Per-cue pacing (a sound longer than a feeling). That needs a word list, or the server reporting
  audio length (creature-server#199).

## Tests

- **`WorldCoreTests`:**
  - what is and isn't a cue, and the words of a line
  - one cue admitted, the second dropped
  - pacing counts a cue as `cue_seconds`, not as letters
  - a scene piece reaches the performer as performed while the record holds the words
  - `performed` round-trips on the item, the intent and the turn, and is absent on an old document
- **`CreatureAgentTests`:**
  - **contracts:** the room and scene contracts offer the cue; the Communicator one doesn't
  - **room path:** the room hears the cue and the intent's text is the words; narration is
    stripped; a second cue is dropped; a trailing cue-only sentence is dropped; a leading one
    joins the next sentence
  - **streamed scene path:** the same rules hold

## How to tell it works

Ask Beaky, in the room, something with feeling in it. Then check four things:

1. The Viewer shows her line with the cue.
2. In Honeycomb, the server's `StreamingAdHocSession.sentence` span has `sentence.tags_performed`.
3. Read the animation back from `/api/v1/animation/ad-hoc/{animationId}`: `mouth_slot` rests
   through the cue.
4. The Communicator shows only the words.
