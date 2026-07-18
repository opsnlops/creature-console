import Foundation
import Testing

@testable import Common

@Suite("AudioError")
struct AudioErrorTests {

    @Test("message returns the case's payload, not a generic description")
    func messageReturnsPayload() {
        #expect(AudioError.fileNotFound("no file").message == "no file")
        #expect(AudioError.noAccess("denied").message == "denied")
        #expect(AudioError.systemError("boom").message == "boom")
        #expect(AudioError.failedToLoad("bad data").message == "bad data")
    }

    @Test("LocalizedError.errorDescription surfaces the payload (not the generic enum text)")
    func localizedErrorSurfacesPayload() {
        let error = AudioError.systemError("Failed to initialize AVAudioPlayer: nope")
        // errorDescription (and therefore localizedDescription) carries the real detail now.
        #expect(error.errorDescription == "Failed to initialize AVAudioPlayer: nope")
        #expect(error.localizedDescription == "Failed to initialize AVAudioPlayer: nope")
    }
}
