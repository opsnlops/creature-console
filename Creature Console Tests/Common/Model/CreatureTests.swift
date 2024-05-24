import XCTest
@testable import Common
@testable import Creature_Console

final class CreatureTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testCreatureInitialization() {
        // Arrange
        let identifier = UUID().uuidString
        let name = "Test Creature"
        let channelOffset = 49
        let audioChannel = 24

        // Act
        let creature = Creature(id: identifier, name: name, channelOffset: channelOffset, audioChannel: audioChannel)

        // Assert
        XCTAssertEqual(creature.id, identifier)
        XCTAssertEqual(creature.name, name)
        XCTAssertEqual(creature.channelOffset, channelOffset)
        XCTAssertEqual(creature.audioChannel, audioChannel)
        }
}
