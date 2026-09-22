import Foundation

/// The predicates the world's own reducers produce — a contract shared with the minds, which
/// phrase them for the model and never see the strings themselves.
public enum WorldFacts {
    /// Which region a character's mind is logged into; `null` once it has left.
    public static let characterRegion = "presence.region"
    /// Whether a person is home, away, or unknown.
    public static let personState = "presence.state"
    /// Every fact about where someone is: `presence.state`, and whatever the minds learn -
    /// `presence.location` "at the doctor", `presence.expected` "back by three". An observed
    /// arrival or departure retracts the reported ones.
    public static let presencePrefix = "presence."
    public static let personAudible = "presence.physically_audible"
    /// A character's pronouns, as its persona states them; told to the world at login.
    public static let characterPronouns = "identity.pronouns"
    /// What was last said in a region: the trigger and the lines, valid for an hour.
    public static let lastScene = "scene.last"
    /// Who a person is, in a phrase April would use: "April's sister". Stated in `world.json`
    /// until a source (the address book, through the Bridge) can say more.
    public static let personDescription = "person.description"
    /// What a person is to April, in her own words: "Mother", "my contractor".
    public static let personRelationship = "person.relationship"
    /// `person:jesse` `visitor.expected` "this afternoon, to look at the deck" — cast by April
    /// (or the Bridge, from a text), usually with an expiry; a person at the door is then
    /// almost certainly them.
    public static let visitorExpected = "visitor.expected"
    /// Who a person a camera saw turned out to be, as April said: "no Beaky, that was just the
    /// postman". Cast by a mind from her words, on the place.
    public static let sightingIdentified = "sighting.identified"

    // Memory, written by the nightly job (step 4b of the judgement plan).
    /// A human-grained memory on the people, places, or house it is about: `{day, when, what,
    /// salience}` — "Jesse came Sunday afternoon and put the boards on the deck". Kept for
    /// years; handed to a mind while recent and salient.
    public static let memoryEpisode = "memory.episode"
    /// A bird's own paragraph about a day, on the bird: what it came to know.
    public static let memoryReflection = "memory.reflection"
    /// What the flock has come to believe about a person, place, thing, or itself, settled
    /// from many days' episodes by the nightly consolidation: `{kind, what, salience, since,
    /// from}` on the subject, in numbered slots (`memory.belief.1`). `kind` is `habit`,
    /// `preference`, `relationship`, or `self` (a bird's own patterns - what landed, what is
    /// worn out). Kept for good; revised, never aged out.
    public static let memoryBelief = "memory.belief"
    public static let beliefKinds: Set<String> = ["habit", "preference", "relationship", "self"]

    /// The kinds of entity a fact's value may point at. A fact whose value is such an id is a
    /// link - `calendar.with = person:jesse` - and the world follows links one hop when it
    /// gathers what a mind is handed.
    public static let linkKinds: Set<String> = [
        "person", "place", "house", "character", "thing", "event", "order",
    ]

    /// The entity a value points at, if it is a link.
    public static func link(in value: WorldJSONValue) -> EntityID? {
        guard case .string(let raw) = value, let colon = raw.firstIndex(of: ":"),
            linkKinds.contains(String(raw[..<colon])), let id = EntityID(rawValue: raw)
        else { return nil }
        return id
    }

    /// A memory's predicate carries whose it is and its day — `memory.episode.kenny.2026-09-13.2`
    /// — so every bird's memory of every day stands beside the others instead of superseding
    /// them. The family is the predicate without either.
    public static func memoryFamily(of predicate: String) -> String? {
        for family in [memoryEpisode, memoryReflection, memoryBelief]
        where predicate == family || predicate.hasPrefix(family + ".") {
            return family
        }
        return nil
    }

    public static let memoryFamilies = [memoryEpisode, memoryReflection, memoryBelief]

    /// The bird a memory belongs to, from its predicate: `memory.belief.kenny.1` → "kenny".
    /// April: "What was Kenny's reflection?" - there was none; one mind remembered for the
    /// flock. Each bird remembers its own night now, and what it is handed is its own.
    public static func memoryOwner(of predicate: String) -> String? {
        guard let family = memoryFamily(of: predicate) else { return nil }
        let rest = predicate.dropFirst(family.count + 1)
        guard let owner = rest.split(separator: ".").first, !owner.isEmpty,
            !isDayOrSlot(owner)
        else { return nil }
        return String(owner)
    }

    /// `character:kenny` → "kenny": the segment a bird's memories carry.
    public static func memoryOwner(for characterID: EntityID) -> String {
        String(characterID.rawValue.split(separator: ":").last ?? "")
    }

    /// The prefix of everything `characterID` remembers in `family`: `memory.episode.kenny.`
    public static func memoryPrefix(_ family: String, of characterID: EntityID) -> String {
        "\(family).\(memoryOwner(for: characterID))."
    }

    /// A day (`2026-09-13`) or a slot number: the segment that follows the owner, and what
    /// stood where the owner now is before memories were owned.
    private static func isDayOrSlot(_ segment: Substring) -> Bool {
        segment.allSatisfy { $0.isNumber || $0 == "-" }
    }

    // The house, through the Home Assistant adapter (creature-house).
    /// A door's lock: `locked` / `unlocked`.
    public static let doorLock = "door.lock"
    /// A door's contact sensor: `open` / `closed`.
    public static let doorState = "door.state"
    /// Motion in a place right now, `true` / `false`.
    public static let motionActive = "motion.active"
    /// A camera saw someone or something at a place, for a few minutes: `seen.person`,
    /// `seen.vehicle`, `seen.animal`.
    public static let seenPrefix = "seen."
    /// A camera watches this place, so nothing seen is itself a fact.
    public static let cameraWatching = "camera.watching"
    /// A measurement of a place: `environment.<predicate>` (`environment.temperature_f`).
    public static let environmentPrefix = "environment."
    /// The lighting scenes the house offers, on `house:<name>`: an array of names.
    public static let houseScenes = "house.scenes"
    /// The lighting scene the house is set to, on `house:<name>`: a name.
    public static let houseScene = "house.scene"
    /// A scene someone just asked for, on `house:<name>`, valid for a couple of minutes: the
    /// mind is told the house is already doing it.
    public static let houseSceneRequested = "house.scene_requested"

    /// What each predicate means, in a sentence a mind can use — the seed for the world's
    /// `fact_kinds`, which a Wizard may edit. Code that produces a predicate is the right place
    /// to say what it means; the world renders facts generically and hands the mind this
    /// glossary for the predicates present, so a new kind of fact needs a sentence here (or a
    /// document in the store), never a phrasing.
    public static let meanings: [String: String] = [
        characterRegion:
            "which room a bird's mind is logged into; the region this scene is in is the room you are in",
        personState: "whether a person is home or away, as far as the house can tell",
        characterPronouns: "a bird's pronouns, as it states them",
        personAudible:
            "whether a person can hear the room right now; the world uses it to choose between speaking aloud and the phone",
        lastScene:
            "what was said aloud in this room last time, in order - a record of words, not of facts: a bird may have been mistaken, and what you know from the world may have changed since. If April asks something again, answer afresh from what you know now, never by repeating a line; a question answered in an earlier scene has not been answered in this one",
        personDescription: "who a person is, in April's words",
        visitorExpected:
            "someone April is expecting, and when; a person turning up then is almost certainly them",
        "departure.due":
            "somewhere April has to be, away from the house, and when she should leave to make it - from her calendar and the travel time to the place",
        memoryEpisode:
            "something that happened, as you remember it - when (in human terms, not a clock), who, what, and how much it mattered; your own memory, kept for years",
        memoryReflection: "what you came to know on a day, in your own words; your own reflection",
        memoryBelief:
            "what you have come to believe over many days - a habit or preference of theirs, what they are to you, or (on yourself) what you tend to do and what is worn out; your own settled view, not an observation; the days it rests on are listed",
        "delivery.expected":
            "a package on its way to the house today: what it is and who is bringing it",
        "delivery.arrived":
            "a package the carrier says it delivered to the house, in the last few hours",
        sightingIdentified:
            "who the person a camera saw there turned out to be, in April's words - a correction to hold onto",
        doorLock:
            "whether the door's deadbolt is thrown, from the smart lock; says nothing about whether the door is open",
        doorState: "whether the door stands open or closed, from its contact sensor",
        motionActive: "the motion sensor in that place is seeing movement right now",
        "seen.person": "a camera's person detector fired there; it cannot tell who",
        "seen.vehicle": "a camera saw a vehicle there; it cannot tell whose",
        "seen.animal": "a camera saw an animal there",
        cameraWatching:
            "a camera watches that place; when it has seen nothing, nothing is there as far as it can tell",
        houseScenes:
            "the lighting scenes the house can set by name; you cannot set them yourself - the house acts when April names one, and you are told here when it does; never say the lights are changing unless told so",
        houseScene: "the lighting scene the house is currently set to",
        houseSceneRequested:
            "April just asked for these lights and the house is setting them right now",
        "environment.temperature_f": "the temperature there, in degrees Fahrenheit",
        "environment.humidity_percent": "relative humidity there, percent",
        "environment.wind_mph": "average wind speed there, miles an hour",
        "environment.rain_today_in": "rain so far today, inches",
        "environment.pressure_hpa":
            "barometric pressure, hectopascals; falling means weather coming",
        "environment.pm25_ugm3":
            "fine particulate air pollution, micrograms per cubic metre; above 35 is unhealthy",
        "environment.power_w": "the whole house's electricity draw right now, watts",
    ]
}

/// The events the house adapter posts, from Home Assistant state changes. Source vocabulary
/// (entity IDs, `on`/`off`) stays in the adapter; the world sees doors, motion, people, and
/// measurements.
public enum HouseEvents {
    public static let sourceKind = "home-assistant"
    public static let doorLocked = WorldEventType(rawValue: "door.locked")!
    public static let doorUnlocked = WorldEventType(rawValue: "door.unlocked")!
    public static let doorOpened = WorldEventType(rawValue: "door.opened")!
    public static let doorClosed = WorldEventType(rawValue: "door.closed")!
    public static let motionDetected = WorldEventType(rawValue: "motion.detected")!
    public static let motionCleared = WorldEventType(rawValue: "motion.cleared")!
    /// A camera's smart detection: the best source of what is happening around the house.
    public static let personSeen = WorldEventType(rawValue: "camera.person_seen")!
    public static let vehicleSeen = WorldEventType(rawValue: "camera.vehicle_seen")!
    public static let animalSeen = WorldEventType(rawValue: "camera.animal_seen")!
    /// The end of a long detection: a vehicle that sat in the driveway for two hours has
    /// gone, a person who was about for an hour is no longer seen. `after_seconds` in the
    /// payload says how long they were there. The moment the cleaners leave.
    public static let personGone = WorldEventType(rawValue: "camera.person_gone")!
    public static let vehicleGone = WorldEventType(rawValue: "camera.vehicle_gone")!
    /// The house says a camera watches a place (at startup, per detection mapping).
    public static let cameraWatching = WorldEventType(rawValue: "camera.watching")!
    /// The house's own word on the calendar: an away event's leave-by time is near
    /// (`departure.soon`, the heads-up) or here (`departure.now`), and April is still home.
    public static let departureSoon = WorldEventType(rawValue: "departure.soon")!
    public static let departureNow = WorldEventType(rawValue: "departure.now")!
    /// A reminder fell due while April was home: "call the vet, due at 4:00 PM".
    public static let reminderDue = WorldEventType(rawValue: "reminder.due")!
    public static let personArrived = WorldEventType(rawValue: "person.arrived")!
    public static let personLeft = WorldEventType(rawValue: "person.left")!
    public static let measurementChanged = WorldEventType(
        rawValue: "environment.measurement_changed")!
    /// The house says which scenes it offers (at startup, and when they change).
    public static let scenesOffered = WorldEventType(rawValue: "house.scenes_offered")!
    /// Someone asked for a scene ("Beaky, set the lights to normal evening"); the house acts.
    public static let sceneRequested = WorldEventType(rawValue: "house.scene_requested")!
    /// The house set the scene.
    public static let sceneActivated = WorldEventType(rawValue: "house.scene_activated")!
}
