import Foundation

/// A Data Transfer Object for the DMX Fixture List
public struct DmxFixtureListDTO: Codable {

    public var count: Int32
    public var items: [DmxFixture]

}
