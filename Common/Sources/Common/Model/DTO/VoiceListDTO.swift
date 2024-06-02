import Foundation

/// A Data Transfer Object for the Voice List
public struct VoiceListDTO: Codable {

    public var count: Int32
    public var items: [Voice]

}
