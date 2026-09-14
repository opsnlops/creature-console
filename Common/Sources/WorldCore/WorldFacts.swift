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
