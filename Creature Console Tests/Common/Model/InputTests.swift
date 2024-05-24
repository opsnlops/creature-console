import XCTest
@testable import Common
@testable import Creature_Console

final class InputTests: XCTestCase {

    func testInitialization() {
        // Arrange
        let name = "head_tilt"
        let slot: UInt16 = 1
        let width: UInt8 = 2
        let joystickAxis: UInt8 = 3

        // Act
        let input = Input(name: name, slot: slot, width: width, joystickAxis: joystickAxis)

        // Assert
        XCTAssertEqual(input.name, name)
        XCTAssertEqual(input.slot, slot)
        XCTAssertEqual(input.width, width)
        XCTAssertEqual(input.joystickAxis, joystickAxis)
    }

    func testEncodingAndDecoding() throws {
        // Arrange
        let input = Input(name: "neck_rotate", slot: 2, width: 1, joystickAxis: 4)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // Act
        let data = try encoder.encode(input)
        let decodedInput = try decoder.decode(Input.self, from: data)

        // Assert
        XCTAssertEqual(input, decodedInput)
    }

    func testEquality() {
        // Arrange
        let input1 = Input(name: "beak", slot: 3, width: 2, joystickAxis: 1)
        let input2 = Input(name: "beak", slot: 3, width: 2, joystickAxis: 1)
        let input3 = Input(name: "stand_lean", slot: 4, width: 1, joystickAxis: 0)

        // Assert
        XCTAssertEqual(input1, input2)
        XCTAssertNotEqual(input1, input3)
    }

    func testHashability() {
        // Arrange
        let input1 = Input(name: "clutch", slot: 5, width: 2, joystickAxis: 6)
        var hasher1 = Hasher()
        input1.hash(into: &hasher1)
        let hash1 = hasher1.finalize()

        let input2 = Input(name: "clutch", slot: 5, width: 2, joystickAxis: 6)
        var hasher2 = Hasher()
        input2.hash(into: &hasher2)
        let hash2 = hasher2.finalize()

        // Assert
        XCTAssertEqual(hash1, hash2)
    }

    func testMockInitialization() {
        // Act
        let mockInput = Input.mock()

        // Assert
        XCTAssertFalse(mockInput.name.isEmpty)
        XCTAssertTrue((0...511).contains(mockInput.slot))
        XCTAssertTrue((1...2).contains(mockInput.width))
        XCTAssertTrue((0...7).contains(mockInput.joystickAxis))
    }
}
