import Foundation

/// A Data Transfer Object for the Creature List
public struct CreatureListDTO: Codable {

    public var count: Int32
    public var items: [Creature]

}
