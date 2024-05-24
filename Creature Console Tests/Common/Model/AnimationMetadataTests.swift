import XCTest
@testable import Common
@testable import Creature_Console

class AnimationMetadataTests: XCTestCase {

    func testInitialization() {
        // Arrange
        let id = UUID().uuidString
        let title = "Test Animation"
        let lastUpdated = Date()
        let millisecondsPerFrame: UInt32 = 30
        let note = "Test Note"
        let soundFile = "test_sound.mp3"
        let numberOfFrames: UInt32 = 120
        let multitrackAudio = true

        // Act
        let metadata = AnimationMetadata(
            id: id, title: title, lastUpdated: lastUpdated,
            millisecondsPerFrame: millisecondsPerFrame, note: note, soundFile: soundFile,
            numberOfFrames: numberOfFrames, multitrackAudio: multitrackAudio
        )

        // Assert
        XCTAssertEqual(metadata.id, id)
        XCTAssertEqual(metadata.title, title)
        XCTAssertEqual(metadata.lastUpdated, lastUpdated)
        XCTAssertEqual(metadata.millisecondsPerFrame, millisecondsPerFrame)
        XCTAssertEqual(metadata.note, note)
        XCTAssertEqual(metadata.soundFile, soundFile)
        XCTAssertEqual(metadata.numberOfFrames, numberOfFrames)
        XCTAssertEqual(metadata.multitrackAudio, multitrackAudio)
    }

    func testEncodingAndDecoding() throws {
        // Arrange
        let id = UUID().uuidString
        let metadata = AnimationMetadata(
            id: id, title: "Test Animation", lastUpdated: Date(), millisecondsPerFrame: 20,
            note: "Test Note", soundFile: "test_sound.mp3", numberOfFrames: 120,
            multitrackAudio: true)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // Act
        let data = try encoder.encode(metadata)
        let decodedMetadata = try decoder.decode(AnimationMetadata.self, from: data)

        // Assert
        XCTAssertEqual(metadata, decodedMetadata)
    }

    func testEquality() {
        // Arrange
        let id1 = UUID().uuidString
        let id2 = UUID().uuidString
        let metadata1 = AnimationMetadata(
            id: id1, title: "Test Animation", lastUpdated: Date(), millisecondsPerFrame: 20,
            note: "Test Note", soundFile: "test_sound.mp3", numberOfFrames: 120,
            multitrackAudio: true)
        let metadata2 = AnimationMetadata(
            id: id1, title: "Test Animation", lastUpdated: Date(), millisecondsPerFrame: 20,
            note: "Test Note", soundFile: "test_sound.mp3", numberOfFrames: 120,
            multitrackAudio: true)
        let metadata3 = AnimationMetadata(
            id: id2, title: "Another Animation", lastUpdated: Date(), millisecondsPerFrame: 25,
            note: "Another Note", soundFile: "another_sound.mp3", numberOfFrames: 150,
            multitrackAudio: false)

        // Assert
        XCTAssertEqual(metadata1, metadata2)
        XCTAssertNotEqual(metadata1, metadata3)
    }

    func testHashability() {
        // Arrange
        let id = UUID().uuidString
        let date = Date()
        let metadata1 = AnimationMetadata(
            id: id, title: "Test Animation", lastUpdated: date, millisecondsPerFrame: 20,
            note: "Test Note", soundFile: "test_sound.mp3", numberOfFrames: 120,
            multitrackAudio: true)
        var hasher1 = Hasher()
        metadata1.hash(into: &hasher1)
        let hash1 = hasher1.finalize()

        let metadata2 = AnimationMetadata(
            id: id, title: "Test Animation", lastUpdated: date, millisecondsPerFrame: 20,
            note: "Test Note", soundFile: "test_sound.mp3", numberOfFrames: 120,
            multitrackAudio: true)
        var hasher2 = Hasher()
        metadata2.hash(into: &hasher2)
        let hash2 = hasher2.finalize()

        // Assert
        XCTAssertEqual(hash1, hash2)
    }

    func testMockInitialization() {
        // Act
        let mockMetadata = AnimationMetadata.mock()

        // Assert
        XCTAssertFalse(mockMetadata.title.isEmpty)
        XCTAssertNotNil(mockMetadata.lastUpdated)
        XCTAssertTrue(mockMetadata.millisecondsPerFrame > 0)
        XCTAssertFalse(mockMetadata.note.isEmpty)
        XCTAssertFalse(mockMetadata.soundFile.isEmpty)
        XCTAssertTrue(mockMetadata.numberOfFrames > 0)
    }
}
