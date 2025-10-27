import Foundation
import Testing

@testable import Common

@Suite("Ad-hoc asset DTO decoding")
struct AdHocAssetDTOTests {

    @Test("decodes ad-hoc animation list payload")
    func decodesAnimationList() throws {
        let json = """
            {
                "count": 1,
                "items": [
                    {
                        "animation_id": "adhoc-123",
                        "created_at": "2025-10-26T01:02:03.456Z",
                        "metadata": {
                            "animation_id": "adhoc-123",
                            "title": "Crowd riff",
                            "milliseconds_per_frame": 33,
                            "note": "Saturday show",
                            "sound_file": "adhoc_123.wav",
                            "number_of_frames": 120,
                            "multitrack_audio": false
                        }
                    }
                ]
            }
            """
        let data = Data(json.utf8)
        let dto = try JSONDecoder().decode(AdHocAnimationListDTO.self, from: data)
        #expect(dto.count == 1)
        #expect(dto.items.count == 1)
        let entry = dto.items[0]
        #expect(entry.animationId == "adhoc-123")
        #expect(entry.metadata.title == "Crowd riff")
        #expect(entry.createdAt != nil)
    }

    @Test("decodes ad-hoc sound list payload")
    func decodesSoundList() throws {
        let json = """
            {
                "count": 1,
                "items": [
                    {
                        "animation_id": "adhoc-123",
                        "created_at": "2025-10-26T01:02:03.456Z",
                        "sound_file": "/tmp/creature-adhoc/file.wav",
                        "sound": {
                            "file_name": "file.wav",
                            "size": 1024,
                            "transcript": "Hi there",
                            "lipsync": "file.json"
                        }
                    }
                ]
            }
            """
        let data = Data(json.utf8)
        let dto = try JSONDecoder().decode(AdHocSoundListDTO.self, from: data)
        #expect(dto.count == 1)
        #expect(dto.items.count == 1)
        let entry = dto.items[0]
        #expect(entry.animationId == "adhoc-123")
        #expect(entry.sound.fileName == "file.wav")
        #expect(entry.createdAt != nil)
        #expect(entry.soundFilePath.contains("file.wav"))
    }
}
