# Memories a bird chooses to share (#243)

April asked the birds whether to keep letting them read each other's memories. They agreed: keep
it, but each bird decides per memory, and the owner always stays attached. Caroll: "Could there
be a little 'share this memory' gate?" Mango: "keep the source attached, so learning what someone
remembers never turns it into my own firsthand memory." April: "Just leave the month's worth of
memories alone. Open an issue and let's make this real."

Then the birds settled the old memories themselves. Mango: "the application can treat missing
flags as private until they're explicitly shared." Kenny: "Old memories get privacy too, even
before anyone adds a mark." So nothing already written is rewritten, and a memory without a mark
is private.

## Today

A bird's page carries only its own memories (`rememberedBy`). Its lookup tools return every
bird's `memory.*` facts, because memories are filed on whoever they are about and aren't
world-only. `query_timeline` filters nothing for a mind, so a memory write, or a world-only fact
such as a phone number, could reach a bird through its raw event.

## The change

1. **The bird chooses (agent, MemoryJob).** At 3:30 AM every episode and belief in the bird's
   JSON carries `"shared": true | false`, and the reflection `"reflection_shared"`. The prompts
   say what it means: shared lets the other birds look the memory up, and they'll see it's yours;
   not shared keeps it to yourself. The value of each memory fact records it as `"shared"`. The
   mark lives in the fact itself, so it travels through backups and dump/restore with the memory
   (Mango and Kenny asked for that).
2. **The World enforces it (WorldMCP).** A mind's tool call names the mind
   (`_meta.mind = "character:beaky"`). `visible()` drops another bird's memory unless its value
   says `"shared": true`. Sharing is opt-in, so the month written before the birds could choose
   (no mark) stays with its bird, as they asked. A bird's own memories always come back. A call
   that doesn't name its mind (an older agent) sees only memories marked shared.
3. **The timeline is gated too.** For a mind, `query_timeline` drops a `facts.given` event whose
   fact is world-only or another bird's private memory. This also closes the world-only hole.
4. **The owner stays attached (agent, ModelTools contract).** Another bird's memories reach you
   only when that bird chose to share them; one that does is theirs: "Caroll remembers …", never
   your own memory or a fact you know firsthand. (2.100.0 said only "shared with you", and Beaky
   took it to mean she could read all of Caroll's; 2.100.1 says what the gate is.)
5. **The Viewer** shows a lock on a memory its bird kept private.

## Not in this change

`query_day` hands a mind the day's `learned` lines, which may include world-only facts: #244.

## Versions

World 0.58.0, agent 2.100.0, Viewer 0.17.0.
