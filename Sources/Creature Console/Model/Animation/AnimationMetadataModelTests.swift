import Common
import Foundation
import SwiftData
import Testing

@testable import Creature_Console

@Suite("AnimationMetadataModel basics")
struct AnimationMetadataModelTests {

    @Test("initializes with provided values")
    func initializesWithValues() throws {
        let id: AnimationIdentifier = "anim_123"
        let title = "Test Animation"
        let lastUpdated = Date()
        let msPerFrame: UInt32 = 20
        let note = "Test note"
        let soundFile = "test.wav"
        let numberOfFrames: UInt32 = 100
        let multitrackAudio = true

        let model = AnimationMetadataModel(
            id: id,
            title: title,
            lastUpdated: lastUpdated,
            millisecondsPerFrame: msPerFrame,
            note: note,
            soundFile: soundFile,
            numberOfFrames: numberOfFrames,
            multitrackAudio: multitrackAudio
        )

        #expect(model.id == id)
        #expect(model.title == title)
        #expect(model.lastUpdated == lastUpdated)
        #expect(model.millisecondsPerFrame == msPerFrame)
        #expect(model.note == note)
        #expect(model.soundFile == soundFile)
        #expect(model.numberOfFrames == numberOfFrames)
        #expect(model.multitrackAudio == multitrackAudio)
    }

    @Test("converts from DTO")
    func convertsFromDTO() throws {
        let dto = Common.AnimationMetadata(
            id: "anim_456",
            title: "DTO Animation",
            lastUpdated: Date(),
            millisecondsPerFrame: 30,
            note: "DTO note",
            soundFile: "dto.wav",
            numberOfFrames: 200,
            multitrackAudio: false
        )

        let model = AnimationMetadataModel(dto: dto)

        #expect(model.id == dto.id)
        #expect(model.title == dto.title)
        #expect(model.lastUpdated == dto.lastUpdated)
        #expect(model.millisecondsPerFrame == dto.millisecondsPerFrame)
        #expect(model.note == dto.note)
        #expect(model.soundFile == dto.soundFile)
        #expect(model.numberOfFrames == dto.numberOfFrames)
        #expect(model.multitrackAudio == dto.multitrackAudio)
    }

    @Test("converts to DTO")
    func convertsToDTO() throws {
        let lastUpdated = Date()
        let model = AnimationMetadataModel(
            id: "anim_789",
            title: "Model Animation",
            lastUpdated: lastUpdated,
            millisecondsPerFrame: 25,
            note: "Model note",
            soundFile: "model.wav",
            numberOfFrames: 150,
            multitrackAudio: true
        )

        let dto = model.toDTO()

        #expect(dto.id == model.id)
        #expect(dto.title == model.title)
        #expect(dto.lastUpdated == model.lastUpdated)
        #expect(dto.millisecondsPerFrame == model.millisecondsPerFrame)
        #expect(dto.note == model.note)
        #expect(dto.soundFile == model.soundFile)
        #expect(dto.numberOfFrames == model.numberOfFrames)
        #expect(dto.multitrackAudio == model.multitrackAudio)
    }

    @Test("round-trips through DTO conversion")
    func roundTripsDTO() throws {
        let originalDTO = Common.AnimationMetadata(
            id: "anim_round",
            title: "Round Trip",
            lastUpdated: Date(),
            millisecondsPerFrame: 33,
            note: "Round trip note",
            soundFile: "round.wav",
            numberOfFrames: 300,
            multitrackAudio: true
        )

        let model = AnimationMetadataModel(dto: originalDTO)
        let convertedDTO = model.toDTO()

        #expect(convertedDTO.id == originalDTO.id)
        #expect(convertedDTO.title == originalDTO.title)
        #expect(convertedDTO.lastUpdated == originalDTO.lastUpdated)
        #expect(convertedDTO.millisecondsPerFrame == originalDTO.millisecondsPerFrame)
        #expect(convertedDTO.note == originalDTO.note)
        #expect(convertedDTO.soundFile == originalDTO.soundFile)
        #expect(convertedDTO.numberOfFrames == originalDTO.numberOfFrames)
        #expect(convertedDTO.multitrackAudio == originalDTO.multitrackAudio)
    }

    @Test("handles nil lastUpdated date")
    func handlesNilLastUpdated() throws {
        let model = AnimationMetadataModel(
            id: "anim_nil",
            title: "Nil Date",
            lastUpdated: nil,
            millisecondsPerFrame: 20,
            note: "",
            soundFile: "",
            numberOfFrames: 0,
            multitrackAudio: false
        )

        #expect(model.lastUpdated == nil)

        // When converting to DTO, nil lastUpdated becomes Date()
        let dto = model.toDTO()
        #expect(dto.lastUpdated != nil)
    }

    @Test("persists in SwiftData context")
    func persistsInSwiftDataContext() async throws {
        let schema = Schema([AnimationMetadataModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let model = AnimationMetadataModel(
            id: "anim_persist",
            title: "Persist Test",
            lastUpdated: Date(),
            millisecondsPerFrame: 20,
            note: "Persist note",
            soundFile: "persist.wav",
            numberOfFrames: 50,
            multitrackAudio: false
        )

        context.insert(model)
        try context.save()

        let fetchDescriptor = FetchDescriptor<AnimationMetadataModel>()
        let results = try context.fetch(fetchDescriptor)

        #expect(results.count == 1)
        #expect(results.first?.id == "anim_persist")
        #expect(results.first?.title == "Persist Test")
    }

    @Test("enforces unique ID constraint")
    func enforcesUniqueID() async throws {
        let schema = Schema([AnimationMetadataModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let model1 = AnimationMetadataModel(
            id: "anim_unique",
            title: "First",
            lastUpdated: Date(),
            millisecondsPerFrame: 20,
            note: "",
            soundFile: "",
            numberOfFrames: 10,
            multitrackAudio: false
        )

        let model2 = AnimationMetadataModel(
            id: "anim_unique",
            title: "Second",
            lastUpdated: Date(),
            millisecondsPerFrame: 30,
            note: "",
            soundFile: "",
            numberOfFrames: 20,
            multitrackAudio: false
        )

        context.insert(model1)
        try context.save()

        context.insert(model2)
        try context.save()

        let fetchDescriptor = FetchDescriptor<AnimationMetadataModel>()
        let results = try context.fetch(fetchDescriptor)

        // SwiftData unique constraint means only one should exist
        #expect(results.count == 1)
        // The second one should have replaced the first
        #expect(results.first?.title == "Second")
    }
}
