import Foundation
import Testing

@testable import Common

@Suite("Sound model tests")
struct SoundTests {

    @Test("initializes with all properties")
    func initializesWithAllProperties() {
        let sound = Sound(
            fileName: "test.mp3",
            size: 12345,
            transcript: "Hello world",
            lipsync: "test.json"
        )

        #expect(sound.fileName == "test.mp3")
        #expect(sound.size == 12345)
        #expect(sound.transcript == "Hello world")
        #expect(sound.lipsync == "test.json")
        #expect(sound.id == "test.mp3")  // id should equal fileName
    }

    @Test("id property returns fileName")
    func idPropertyReturnsFileName() {
        let sound = Sound(fileName: "mySound.wav", size: 999, transcript: "")

        #expect(sound.id == sound.fileName)
        #expect(sound.id == "mySound.wav")
    }

    @Test("encodes to JSON with snake_case")
    func encodesToJSONWithSnakeCase() throws {
        let sound = Sound(
            fileName: "audio.mp3",
            size: 54321,
            transcript: "Test transcript",
            lipsync: "audio.json"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(sound)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["file_name"] as? String == "audio.mp3")
        #expect(json?["size"] as? Int == 54321)
        #expect(json?["transcript"] as? String == "Test transcript")
        #expect(json?["lipsync"] as? String == "audio.json")
    }

    @Test("decodes from JSON with snake_case")
    func decodesFromJSONWithSnakeCase() throws {
        let jsonString = """
            {
                "file_name": "voice.wav",
                "size": 98765,
                "transcript": "This is a test",
                "lipsync": "voice.json"
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let sound = try decoder.decode(Sound.self, from: data)

        #expect(sound.fileName == "voice.wav")
        #expect(sound.size == 98765)
        #expect(sound.transcript == "This is a test")
        #expect(sound.lipsync == "voice.json")
    }

    @Test("decodes when lipsync missing")
    func decodesWhenLipsyncMissing() throws {
        let jsonString = """
            {
                "file_name": "voice.wav",
                "size": 98765,
                "transcript": "This is a test"
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let sound = try decoder.decode(Sound.self, from: data)

        #expect(sound.fileName == "voice.wav")
        #expect(sound.lipsync.isEmpty)
    }

    @Test("round-trip encoding preserves data")
    func roundTripEncodingPreservesData() throws {
        let original = Sound(
            fileName: "roundtrip.mp3",
            size: 456789,
            transcript: "Round trip test",
            lipsync: "roundtrip.json"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Sound.self, from: data)

        #expect(decoded.fileName == original.fileName)
        #expect(decoded.size == original.size)
        #expect(decoded.transcript == original.transcript)
        #expect(decoded.lipsync == original.lipsync)
    }

    @Test("equality compares all fields")
    func equalityComparesAllFields() {
        let sound1 = Sound(
            fileName: "same.mp3", size: 100, transcript: "Same", lipsync: "same.json")
        let sound2 = Sound(
            fileName: "same.mp3", size: 100, transcript: "Same", lipsync: "same.json")
        let sound3 = Sound(
            fileName: "different.mp3", size: 100, transcript: "Same", lipsync: "same.json")
        let sound4 = Sound(
            fileName: "same.mp3", size: 200, transcript: "Same", lipsync: "same.json")
        let sound5 = Sound(
            fileName: "same.mp3", size: 100, transcript: "Different", lipsync: "same.json")
        let sound6 = Sound(
            fileName: "same.mp3", size: 100, transcript: "Same", lipsync: "different.json")

        #expect(sound1 == sound2)
        #expect(sound1 != sound3)  // Different fileName
        #expect(sound1 != sound4)  // Different size
        #expect(sound1 != sound5)  // Different transcript
        #expect(sound1 != sound6)  // Different lipsync
    }

    @Test("hashing is consistent with equality")
    func hashingConsistentWithEquality() {
        let sound1 = Sound(
            fileName: "same.mp3", size: 100, transcript: "Same", lipsync: "same.json")
        let sound2 = Sound(
            fileName: "same.mp3", size: 100, transcript: "Same", lipsync: "same.json")

        var hasher1 = Hasher()
        sound1.hash(into: &hasher1)

        var hasher2 = Hasher()
        sound2.hash(into: &hasher2)

        #expect(hasher1.finalize() == hasher2.finalize())
    }

    @Test("mock creates valid sound")
    func mockCreatesValidSound() {
        let mock = Sound.mock()

        #expect(mock.fileName == "amazingSound.mp3")
        #expect(mock.size == 3_409_834)
        #expect(mock.transcript == "")
        #expect(mock.lipsync == "")
    }

    @Test("handles empty transcript")
    func handlesEmptyTranscript() throws {
        let sound = Sound(fileName: "no_transcript.mp3", size: 1000, transcript: "")

        #expect(sound.transcript == "")
        #expect(sound.lipsync == "")

        let encoder = JSONEncoder()
        let data = try encoder.encode(sound)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Sound.self, from: data)

        #expect(decoded.transcript == "")
    }

    @Test("handles long transcript")
    func handlesLongTranscript() throws {
        let longText = String(repeating: "This is a very long transcript. ", count: 100)
        let sound = Sound(
            fileName: "long.mp3", size: 5000, transcript: longText, lipsync: "long.json")

        #expect(sound.transcript == longText)
        #expect(sound.lipsync == "long.json")

        let encoder = JSONEncoder()
        let data = try encoder.encode(sound)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Sound.self, from: data)

        #expect(decoded.transcript == longText)
    }

    @Test("handles various file extensions")
    func handlesVariousFileExtensions() throws {
        let extensions = [".mp3", ".wav", ".ogg", ".flac", ".m4a", ".aac"]

        for ext in extensions {
            let fileName = "sound\(ext)"
            let sound = Sound(
                fileName: fileName, size: 1000, transcript: "Test", lipsync: "lip.json")

            let encoder = JSONEncoder()
            let data = try encoder.encode(sound)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(Sound.self, from: data)

            #expect(decoded.fileName == fileName)
        }
    }

    @Test("handles zero size")
    func handlesZeroSize() throws {
        let sound = Sound(fileName: "empty.mp3", size: 0, transcript: "")

        #expect(sound.size == 0)

        let encoder = JSONEncoder()
        let data = try encoder.encode(sound)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Sound.self, from: data)

        #expect(decoded.size == 0)
    }

    @Test("handles maximum UInt32 size")
    func handlesMaxSize() throws {
        let maxSize: UInt32 = UInt32.max
        let sound = Sound(fileName: "huge.mp3", size: maxSize, transcript: "")

        #expect(sound.size == maxSize)

        let encoder = JSONEncoder()
        let data = try encoder.encode(sound)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Sound.self, from: data)

        #expect(decoded.size == maxSize)
    }

    @Test("handles special characters in transcript")
    func handlesSpecialCharactersInTranscript() throws {
        let specialTranscripts = [
            "Hello, world!",
            "Quote: \"test\"",
            "Newline:\ntest",
            "Unicode: 你好",
            "Emoji: 🎵🎶",
        ]

        for transcript in specialTranscripts {
            let sound = Sound(
                fileName: "test.mp3",
                size: 100,
                transcript: transcript,
                lipsync: "lip.json"
            )

            let encoder = JSONEncoder()
            let data = try encoder.encode(sound)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(Sound.self, from: data)

            #expect(decoded.transcript == transcript)
            #expect(decoded.lipsync == "lip.json")
        }
    }

    @Test("generate lip sync request encodes with snake_case keys")
    func generateLipSyncRequestEncodesSnakeCase() throws {
        let request = GenerateLipSyncRequestDTO(soundFile: "voice.wav", allowOverwrite: true)

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["sound_file"] as? String == "voice.wav")
        #expect(json?["allow_overwrite"] as? Bool == true)
    }

    @Test("generate lip sync request defaults allow_overwrite to false")
    func generateLipSyncRequestDefaultsOverwriteToFalse() throws {
        let request = GenerateLipSyncRequestDTO(soundFile: "voice.wav")

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["allow_overwrite"] as? Bool == false)
    }
}
