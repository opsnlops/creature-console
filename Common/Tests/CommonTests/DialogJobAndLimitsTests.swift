import Foundation
import Testing

@testable import Common

@Suite("Dialog job result + cache type")
struct DialogJobModelsTests {

    @Test("JobType decodes the dialog case")
    func decodesDialogJobType() throws {
        struct Wrapper: Decodable { let type: JobType }
        let data = #"{"type":"dialog"}"#.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(Wrapper.self, from: data)
        #expect(wrapper.type == .dialog)
        #expect(JobType.dialog.rawValue == "dialog")
    }

    @Test("DialogJobResult decodes from the job result JSON string")
    func decodesDialogJobResult() throws {
        let resultJSON = """
            {
              "animation_id": "400b47b2-4ab0-462f-8101-c81b5f187452",
              "number_of_frames": 1228,
              "milliseconds_per_frame": 20,
              "duration_seconds": 24.56,
              "persistence": "permanent",
              "autoplayed": false
            }
            """
        let completion = JobCompletion(
            jobId: "j1", jobType: .dialog, status: .completed, result: resultJSON, details: nil)
        let result = completion.decodeResult(as: DialogJobResult.self)
        #expect(result?.animationId == "400b47b2-4ab0-462f-8101-c81b5f187452")
        #expect(result?.numberOfFrames == 1228)
        #expect(result?.millisecondsPerFrame == 20)
        #expect(result?.durationSeconds == 24.56)
        #expect(result?.persistence == "permanent")
        #expect(result?.autoplayed == false)
    }

    @Test("CacheType decodes the dialog-script-list case")
    func decodesDialogCacheType() throws {
        struct Wrapper: Decodable { let cache_type: CacheType }
        let data = #"{"cache_type":"dialog-script-list"}"#.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(Wrapper.self, from: data)
        #expect(wrapper.cache_type == .dialogScriptList)
        #expect(CacheType.dialogScriptList.rawValue == "dialog-script-list")
    }
}

@Suite("Dialog validation limits")
struct DialogLimitsTests {

    @Test("limits match the server constants")
    func limitsMatchServer() {
        #expect(DialogLimits.maxTurns == 200)
        #expect(DialogLimits.maxTurnText == 4096)
        #expect(DialogLimits.maxTitle == 256)
        #expect(DialogLimits.maxNotes == 16384)
    }
}
