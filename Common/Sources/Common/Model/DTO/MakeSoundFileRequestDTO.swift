import Foundation

/// A struct that defines a request to the API to create a sound file
public struct MakeSoundFileRequestDTO: Codable {
    public var creature_id: CreatureIdentifier
    public var title: String
    public var text: String

    public init(creature_id: CreatureIdentifier, title: String, text: String) {
        self.creature_id = creature_id
        self.title = title
        self.text = text
    }
}
