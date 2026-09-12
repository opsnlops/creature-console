# Personas

One file per resident. The text of each is what goes into that mind's `llmSystemPrompt`
(`/etc/creature/agent/<instance>.yaml`); the file here is the versioned source, the YAML is the
deployment. Personality lives in the agent, never in the world or in triggers
(`beakys-world.md` §2, §8): the world supplies occasions and facts, the character supplies voice
and attitude.

Keep each persona to what the model needs to *be* the character — who they are, how they talk,
what they care about, how they feel about the others — and keep it speech-clean (no emoji; the
words are spoken). The conversation contract (`CharacterMind.contract`) is appended by the
agent and must not be repeated here.
