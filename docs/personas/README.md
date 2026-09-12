# Personas

One file per resident, `<bird>.yaml`. This is what each mind *is*: the agent renders it into the
model's system prompt in sections (who you are, how you talk, what you care about, who is here
and how you feel about them, running jokes, never), followed by "What you know" from the world
and the conversation or scene. Personality lives here and nowhere else (`beakys-world.md` §2,
§8): the world supplies occasions and facts, the persona supplies voice and attitude.

| Key | Required | What it is |
| --- | --- | --- |
| `name` | yes | the character's spoken name |
| `version` | no (1) | bump it when you edit; every span carries `agent.persona_version` = `name/version` |
| `pronouns` | no | rendered after the name, and sent to the world at login so the other birds are told them (`identity.pronouns`); never write another bird's pronouns into your file |
| `about` | yes | who this character is, a paragraph or two |
| `voice` | no | how they talk: length, tone, tics |
| `cares_about`, `avoids` | no | lists |
| `relationships` | no | entity ID → how this character feels about them, as a string or as `{pronouns, feeling}`; **only the ones present are rendered**, from the world's presence facts or the scene's participants. `pronouns` here is what *this* character believes; the world's `identity.pronouns` fact (from the other bird's own file, at its login) outranks it |
| `running_jokes` | no | list |
| `never` | no | hard rules, rendered last |

Keep it speech-clean (the words are spoken) and do not repeat the conversation contract; the
agent appends that. Deploy a file to `/etc/creature/agent/personas/<bird>.yaml` and point the
mind at it with `personaPath` in `/etc/creature/agent/<bird>.yaml`; the package installs these
three as a starting point and never overwrites an edited one. A mind without `personaPath`
uses its plain `llmSystemPrompt` as before. Restart the mind to pick up an edit.
