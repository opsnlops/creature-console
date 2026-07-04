import Testing

@testable import Common

@Suite("soundBasename reduces stored references to a basename")
struct SoundBasenameTests {

    @Test("passes a bare basename through unchanged")
    func bareBasename() {
        #expect(soundBasename("hello.wav") == "hello.wav")
    }

    @Test("reduces a permanent dialog reference (dialog/<uuid>.wav)")
    func permanentDialogReference() {
        #expect(
            soundBasename("dialog/17b8fd4d-d67b-4904-9e66-a8b8fd71698c.wav")
                == "17b8fd4d-d67b-4904-9e66-a8b8fd71698c.wav")
    }

    @Test("reduces an absolute ad-hoc reference (/tmp/creature-adhoc/…)")
    func absoluteAdHocReference() {
        // The exact shape that broke sharing: animation.metadata.sound_file for
        // an ad-hoc render is an absolute path.
        #expect(
            soundBasename("/tmp/creature-adhoc/dialog_17b8fd4d-d67b-4904-9e66-a8b8fd71698c.wav")
                == "dialog_17b8fd4d-d67b-4904-9e66-a8b8fd71698c.wav")
    }

    @Test("handles an empty string without crashing")
    func emptyString() {
        #expect(soundBasename("") == "")
    }
}
