import Foundation

/// The predicates the world's own reducers produce — a contract shared with the minds, which
/// phrase them for the model and never see the strings themselves.
public enum WorldFacts {
    /// Which region a character's mind is logged into; `null` once it has left.
    public static let characterRegion = "presence.region"
    /// Whether a person is home, away, or unknown.
    public static let personState = "presence.state"
    public static let personAudible = "presence.physically_audible"
    /// A character's pronouns, as its persona states them; told to the world at login.
    public static let characterPronouns = "identity.pronouns"
    /// What was last said in a region: the trigger and the lines, valid for an hour.
    public static let lastScene = "scene.last"
    /// Who a person is, in a phrase April would use: "April's sister". Stated in `world.json`
    /// until a source (the address book, through the Bridge) can say more.
    public static let personDescription = "person.description"
    /// `person:jesse` `visitor.expected` "this afternoon, to look at the deck" — cast by April
    /// (or the Bridge, from a text), usually with an expiry; a person at the door is then
    /// almost certainly them.
    public static let visitorExpected = "visitor.expected"

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
        lastScene: "the last thing said aloud in this room: who said what, in order",
        personDescription: "who a person is, in April's words",
        visitorExpected:
            "someone April is expecting, and when; a person turning up then is almost certainly them",
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
    /// The house says a camera watches a place (at startup, per detection mapping).
    public static let cameraWatching = WorldEventType(rawValue: "camera.watching")!
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
