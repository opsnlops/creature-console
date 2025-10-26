import Foundation
import Testing

@testable import Common

@Suite("Job model decoding")
struct JobModelsTests {

    @Test("decodes known job types and defaults unknown")
    func decodesJobType() throws {
        let decoder = JSONDecoder()

        struct Wrapper: Decodable {
            let type: JobType
        }

        let knownData = #"{"type":"lip-sync"}"#.data(using: .utf8)!
        let known = try decoder.decode(Wrapper.self, from: knownData)
        #expect(known.type == .lipSync)

        let adHocData = #"{"type":"ad-hoc-speech"}"#.data(using: .utf8)!
        let adHoc = try decoder.decode(Wrapper.self, from: adHocData)
        #expect(adHoc.type == .adHocSpeech)

        let stagedData = #"{"type":"ad-hoc-speech-prepare"}"#.data(using: .utf8)!
        let staged = try decoder.decode(Wrapper.self, from: stagedData)
        #expect(staged.type == .adHocSpeechPrepare)

        let unknownData = #"{"type":"image-render"}"#.data(using: .utf8)!
        let unknown = try decoder.decode(Wrapper.self, from: unknownData)
        #expect(unknown.type == .unknown)
    }

    @Test("decodes job status values and defaults unknown")
    func decodesJobStatus() throws {
        let decoder = JSONDecoder()

        struct Wrapper: Decodable {
            let status: JobStatus
        }

        let runningData = #"{"status":"running"}"#.data(using: .utf8)!
        let running = try decoder.decode(Wrapper.self, from: runningData)
        #expect(running.status == .running)
        #expect(running.status.isTerminal == false)

        let unknownData = #"{"status":"waiting"}"#.data(using: .utf8)!
        let unknown = try decoder.decode(Wrapper.self, from: unknownData)
        #expect(unknown.status == .unknown)

        let completedData = #"{"status":"completed"}"#.data(using: .utf8)!
        let completed = try decoder.decode(Wrapper.self, from: completedData)
        #expect(completed.status.isTerminal == true)
    }

    @Test("decodes job created response")
    func decodesJobCreatedResponse() throws {
        let json = """
            {
                "job_id": "123",
                "job_type": "lip-sync",
                "message": "Queued"
            }
            """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(JobCreatedResponse.self, from: data)

        #expect(decoded.jobId == "123")
        #expect(decoded.jobType == .lipSync)
        #expect(decoded.message == "Queued")
    }

    @Test("decodes job progress and parses details")
    func decodesJobProgress() throws {
        let json = """
            {
                "job_id": "abc",
                "job_type": "lip-sync",
                "status": "running",
                "progress": 0.5,
                "details": "{\\"sound_file\\":\\"voice.wav\\",\\"allow_overwrite\\":false}"
            }
            """
        let data = Data(json.utf8)
        let progress = try JSONDecoder().decode(JobProgress.self, from: data)

        #expect(progress.jobId == "abc")
        #expect(progress.jobType == .lipSync)
        #expect(progress.status == .running)
        #expect(progress.progress == 0.5)

        let details: LipSyncJobDetails? = progress.decodeDetails(as: LipSyncJobDetails.self)
        #expect(details?.soundFile == "voice.wav")
        #expect(details?.allowOverwrite == false)
    }

    @Test("decodes job completion and parses details")
    func decodesJobCompletion() throws {
        let json = """
            {
                "job_id": "xyz",
                "job_type": "lip-sync",
                "status": "completed",
                "result": "{\\"foo\\":\\"bar\\"}",
                "details": "{\\"sound_file\\":\\"voice.wav\\",\\"allow_overwrite\\":true}"
            }
            """
        let data = Data(json.utf8)
        let completion = try JSONDecoder().decode(JobCompletion.self, from: data)

        #expect(completion.jobId == "xyz")
        #expect(completion.status == .completed)
        #expect(completion.result == "{\"foo\":\"bar\"}")

        let details: LipSyncJobDetails? = completion.decodeDetails(as: LipSyncJobDetails.self)
        #expect(details?.soundFile == "voice.wav")
        #expect(details?.allowOverwrite == true)
    }

    @Test("decodes ad-hoc speech job result payload")
    func decodesAdHocJobResult() throws {
        let json = """
            {
                "job_id": "prep-1",
                "job_type": "ad-hoc-speech-prepare",
                "status": "completed",
                "result": "{\\"animation_id\\":\\"A1\\",\\"sound_file\\":\\"/tmp/foo.wav\\",\\"resume_playlist\\":true,\\"temp_directory\\":\\"/tmp/dir\\",\\"auto_play\\":false,\\"playback_triggered\\":false}"
            }
            """
        let data = Data(json.utf8)
        let completion = try JSONDecoder().decode(JobCompletion.self, from: data)

        #expect(completion.jobType == .adHocSpeechPrepare)
        #expect(completion.decodeResult(as: AdHocSpeechJobResult.self)?.animationId == "A1")
        #expect(completion.decodeResult(as: AdHocSpeechJobResult.self)?.playbackTriggered == false)
    }
}
