import Common
import Foundation
import SwiftData
import Testing

@testable import Creature_Console

@Suite("SoundModel basics")
struct SoundModelTests {

    @Test("initializes with provided values")
    func initializesWithValues() throws {
        let id: SoundIdentifier = "sound_123.wav"
        let size: UInt32 = 1024
        let transcript = "Test transcript"

        let lipsync = "Test lipsync.json"

        let model = SoundModel(id: id, size: size, transcript: transcript, lipsync: lipsync)

        #expect(model.id == id)
        #expect(model.size == size)
        #expect(model.transcript == transcript)
        #expect(model.lipsync == lipsync)
    }

    @Test("converts from DTO")
    func convertsFromDTO() throws {
        let dto = Common.Sound(
            fileName: "dto_sound.wav",
            size: 2048,
            transcript: "DTO transcript",
            lipsync: "dto.json"
        )
        let model = SoundModel(dto: dto)

        #expect(model.id == dto.fileName)
        #expect(model.size == dto.size)
        #expect(model.transcript == dto.transcript)
        #expect(model.lipsync == dto.lipsync)
    }

    @Test("converts to DTO")
    func convertsToDTO() throws {
        let model = SoundModel(
            id: "model_sound.wav",
            size: 4096,
            transcript: "Model transcript",
            lipsync: "model.json"
        )
        let dto = model.toDTO()

        #expect(dto.fileName == model.id)
        #expect(dto.size == model.size)
        #expect(dto.transcript == model.transcript)
        #expect(dto.lipsync == model.lipsync)
    }

    @Test("round-trips through DTO conversion")
    func roundTripsDTO() throws {
        let originalDTO = Common.Sound(
            fileName: "round_trip.wav",
            size: 8192,
            transcript: "Round trip transcript",
            lipsync: "round_trip.json"
        )

        let model = SoundModel(dto: originalDTO)
        let convertedDTO = model.toDTO()

        #expect(convertedDTO.fileName == originalDTO.fileName)
        #expect(convertedDTO.size == originalDTO.size)
        #expect(convertedDTO.transcript == originalDTO.transcript)
    }

    @Test("persists in SwiftData context")
    func persistsInSwiftDataContext() async throws {
        let schema = Schema([SoundModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let model = SoundModel(
            id: "persist.wav",
            size: 512,
            transcript: "Persist transcript",
            lipsync: "persist.json"
        )

        context.insert(model)
        try context.save()

        let fetchDescriptor = FetchDescriptor<SoundModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 1)
        #expect(results.first?.id == "persist.wav")
        #expect(results.first?.size == 512)
        #expect(results.first?.transcript == "Persist transcript")
    }

    @Test("enforces unique ID constraint")
    func enforcesUniqueID() async throws {
        let schema = Schema([SoundModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let model1 = SoundModel(
            id: "unique.wav", size: 100, transcript: "First", lipsync: "lip1.json")
        let model2 = SoundModel(
            id: "unique.wav", size: 200, transcript: "Second", lipsync: "lip2.json")

        context.insert(model1)
        try context.save()

        context.insert(model2)
        try context.save()

        let fetchDescriptor = FetchDescriptor<SoundModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 1)
        #expect(results.first?.transcript == "Second")
        #expect(results.first?.size == 200)
    }

    @Test("handles empty transcript")
    func handlesEmptyTranscript() throws {
        let model = SoundModel(id: "no_transcript.wav", size: 256, transcript: "", lipsync: "")

        #expect(model.id == "no_transcript.wav")
        #expect(model.size == 256)
        #expect(model.transcript == "")
    }

    @Test("preserves file extension in ID")
    func preservesFileExtensionInID() throws {
        let ids = ["sound.wav", "sound.mp3", "sound.m4a", "sound.flac"]

        for id in ids {
            let model = SoundModel(id: id, size: 1000, transcript: "Test", lipsync: "lip.json")
            #expect(model.id == id)

            let dto = model.toDTO()
            #expect(dto.fileName == id)
        }
    }

    @Test("queries by ID efficiently")
    func queriesByIDEfficiently() async throws {
        let schema = Schema([SoundModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        // Insert multiple sounds
        let sounds = [
            SoundModel(id: "sound1.wav", size: 100, transcript: "First", lipsync: "lip1.json"),
            SoundModel(id: "sound2.wav", size: 200, transcript: "Second", lipsync: "lip2.json"),
            SoundModel(id: "sound3.wav", size: 300, transcript: "Third", lipsync: ""),
        ]

        for sound in sounds {
            context.insert(sound)
        }
        try context.save()

        // Query for specific sound by ID
        let fetchDescriptor = FetchDescriptor<SoundModel>(
            predicate: #Predicate { $0.id == "sound2.wav" }
        )
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 1)
        #expect(results.first?.id == "sound2.wav")
        #expect(results.first?.size == 200)
        #expect(results.first?.transcript == "Second")
        #expect(results.first?.lipsync == "lip2.json")
    }
}
