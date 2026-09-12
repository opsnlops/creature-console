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
}
