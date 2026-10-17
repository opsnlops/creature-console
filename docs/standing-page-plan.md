# What a bird knows all day, cached (#245)

April: "Anything else we can do to save costs?" After 2.98.1, the cost of a Beaky reply is
almost all one thing. A steady-state reply is ~12k tokens: ~6.7k read from the cache (the shared
contract and glossary, then her persona), nothing written, and ~5.3k sent fresh at $4/M (Sol,
fast tier). That fresh tail is ~2.1¢ of a ~2.3¢ reply.

| In the fresh tail | ≈ tokens |
|---|---|
| Her memories | 2.3k |
| What the world was told (reported) | 1.4k |
| The moment: observed facts, the story, her recent lines, the clock | 1.2k |
| The script | the rest |

2.98.0 made the memories and reported layers cache points, and every scene wrote them afresh,
because both carry what the scene's words call up (2.98.1 took the points back out). This makes
them stable.

## Why the layers move: the words displace the standing page

`PresentWorldKnowledge.currentFacts` adds whoever the words name (people, orders, the newest
orders on order words) to the page's subjects. The page's 30 facts are the newest across all
subjects, and the bird's own memories are trimmed across all of them too. A mention doesn't just
add facts, it pushes standing ones off. Beaky's perspective, 2026-10-17:

| Words | Facts added | Standing facts pushed off |
|---|---|---|
| (none) | 14 memories, 27 reported: the standing page | - |
| "Mango, tell me about the PoE controllers" | 17 | 7 |
| "Is Jesse coming to finish the deck tomorrow?" | 27 | 10 |
| "What did Mom say about Thanksgiving?" | 13 | 5 |

On their own, the standing parts move slowly:

- **Memories** all became current at 3:30 AM and are fixed for the day.
- **Reported** facts are the newest-30 window, so they move whenever the world learns something:
  about 9 times in the afternoon's busiest two hours of chat, against ~50 Beaky calls.

## What the words call up today

Everything else on the page is the same with or without words:

- the people and orders the words name (`WorldMentions`), and the newest orders on order words;
  their page facts, their one-hop links, their stage and folded readings, and the bird's own
  memories on them;
- memories retrieved by the words (`retrievedInPrompt`), and facts a mind or the librarian kept,
  retrieved by the words (`factsRetrievedInPrompt`);
- the calendar's fortnight and the week's reminders on time words (three days and today without);
- kinds that ride only on request (`body.*` on "board", "power", "servo");
- the house scene the words asked for (`houseCommands.request`, utterances only).

## The change

1. **World 0.59.0: the standing page, then what the words call up beside it.** The standing page
   is the page built with no words, exactly. What the words call up is the page built with them,
   less the standing page, with today's caps, so it never takes a standing fact's place. The two
   are gathered at once, so the live line waits no longer than today; a call with words costs one
   more pass of the page's queries. `WorldKnowledgeProviding.page(about:mentionedIn:limit:)`
   returns the facts and the ids of those the words called up, for any provider; `currentFacts`
   is unchanged. The utterance percept and the scene offer carry `called_up` (fact ids), as do
   `query_character_perspective` and `GET /v1/characters/{id}/perspective`. Absent means an older
   World that doesn't mark them. The house scene the words ask for is always called up.

   **Folded entries keep their ids.** The page's folds (the sensors as one `environment.now`,
   the forecasts, each calendar event and reminder) were made with a fresh id on every page, so
   the same fold looked new each time. That would have marked every fold as called up, and two
   folds made in the same instant ordered at random in a cached layer. A fold's id now comes from
   what it folds (FNV-1a of its subject, predicate and readings): the same readings give the same
   id, in every process.
2. **Agent 2.101.0: the standing layers are cache points again.** Memories and reported facts
   each split into standing and called up. The standing memories and then the standing reported
   facts are cache points, steadiest first. What the words called up rides after them, uncached,
   in its own item under its own headings. In a conversation, the turns so far (a cache point)
   come before it, so they can be read back too. A percept without `called_up` (an older World)
   gets today's layout with no layer cache points, so 2.98.0 can't happen again.

   ```
   scene:        [shared | persona] [standing memories ▲] [standing reported ▲]
                 [called up] [moment] [script]
   conversation: [shared | persona] [standing memories ▲] [standing reported ▲]
                 [turns so far ▲] [called up] [moment] [newest]
   ```
3. **Viewer 0.18.0: what the words called up is marked.** The Page panel (pick a bird, type the
   words) shows the called-up facts apart from the standing page, so April can see what stays
   cached all day and what the words brought.

## Found on the way

`knownPeople` keeps only people with a `person.relationship` fact: `people[subject] =
people[subject] ?? nil` assigns a double-optional nil, which removes the key. A name in the
words never calls up someone the world knows only by a description or from the address book.
Its own change: #246.

## Expected

Per Beaky reply: cache read ~6.7k → ~9.5k, fresh ~5.3k → ~2.3k, **~2.3¢ → ~1.1¢**: ~$10–55 a
month, depending on how much April talks with the birds. Cache writes: ~3k on the first call
after 3:30 AM or after a 30-minute gap, and ~1.1k each time the world learns something. A call
with mentions now sees the whole standing page plus what the words called up: a few hundred
tokens more than today, and nothing April taught her gets pushed off by a name.

## Measure after

- Honeycomb, Beaky's chat spans: read per call ~9.5k, writes 0 on most calls, ~1.1k after the
  world learns something.
- The perspective sizes above, standing against called up, through the Page panel.

## Versions

World 0.59.0, agent 2.101.0, Viewer 0.18.0, one release. The World goes first: an agent without
`called_up` keeps today's layout.
