import Common
import Foundation
import OSLog
import SwiftData
import SwiftUI

struct CreateNewCreatureSoundView: View {

    let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "CreateNewCreatureSoundView")

    let server = CreatureServerClient.shared

    @Environment(\.modelContext) private var modelContext

    // Lazily fetched by SwiftData
    @Query(sort: \CreatureModel.name, order: .forward)
    private var creatures: [CreatureModel]

    @State private var errorAlert: ErrorAlert?


    @State var title: String = ""
    @State var text: String = ""
    @State private var creatureId: CreatureIdentifier?


    @State var soundFileName: String?
    @State var currentAction: String = "idle"
    @State private var createSoundTask: Task<Void, Never>? = nil
    @State private var playSoundTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack {

            VStack {
                Form {

                    Section(header: Text("Creature Information")) {
                        Picker("Creature", selection: $creatureId) {
                            ForEach(creatures) { creature in
                                Text(creature.name).tag(creature.id as CreatureIdentifier?)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }

                    Spacer(minLength: 20)

                    Section(header: Text("Sound File Information")) {

                        TextField("Title", text: $title)
                            .textFieldStyle(.roundedBorder)

                        Section(header: Text("Creature Dialog")) {
                            GeometryReader { geometry in
                                TextEditor(text: $text)
                                    .font(.system(size: 16))
                                    .frame(maxHeight: geometry.size.height)
                                    .padding(.horizontal)
                                    .autocorrectionDisabled(false)  // Enable spellcheck and autocorrection
                            }  // GeometryReader
                        }  //Section

                    }  // Section


                    Button {
                        createSoundOnServer()
                    } label: {
                        Label("Create New Sound File", systemImage: "square.and.arrow.down")
                            .symbolRenderingMode(.palette)
                    }
                    .disabled(creatureId == nil || title.isEmpty || text.isEmpty)
                    .frame(maxWidth: .infinity, alignment: .center)


                }  //Form
                .padding()

                HStack {
                    HStack {
                        HStack {
                            Text("File name: \(soundFileName ?? "(not saved)")")

                            if soundFileName != nil {
                                Button(action: {
                                    copySoundFileToClipboard()
                                }) {
                                    Image(systemName: "doc.on.clipboard")
                                        .symbolRenderingMode(.hierarchical)
                                        .opacity(0.3)
                                }
                                .buttonStyle(PlainButtonStyle())

                            }

                            Spacer()
                        }
                        .padding()


                        Button {
                            playSavedSound()
                        } label: {
                            Label("Play", systemImage: "speaker.wave.3")
                                .symbolRenderingMode(.palette)
                        }
                        .disabled(soundFileName == nil)
                        .frame(alignment: .trailing)

                    }
                    .frame(alignment: .leading)

                    Text(currentAction)
                        .frame(width: 50, alignment: .trailing)
                        .font(.caption)

                }


            }  // VStack
            .padding()

        }  // Navigation Stack
        .errorAlert($errorAlert, dismissLabel: "No Music for Us")
        .onDisappear {

            // Clean up if either of these is still running
            playSoundTask?.cancel()
            createSoundTask?.cancel()
        }
    }  // View


    func createSoundOnServer() {
        logger.debug("attempting to create the sound on the server...")


        if let creatureId = creatureId {

            // Stop whatever is in flight
            createSoundTask?.cancel()

            createSoundTask = Task {

                currentAction = "saving"

                // Server 3.23.0+: sound creation is an async job (long text takes a
                // while). Watch it via the shared per-job stream.
                let saveResult = await server.createCreatureSpeechSoundFile(
                    creatureId: creatureId, title: title, text: text)

                switch saveResult {
                case .success(let job):
                    await JobStatusStore.shared.seedQueued(job)
                    for await event in await JobStatusStore.shared.events(forJob: job.jobId) {
                        switch event {
                        case .updated:
                            continue
                        case .terminal(let info):
                            await MainActor.run {
                                if info.status == .completed,
                                    let result = info.result,
                                    let data = result.data(using: .utf8),
                                    let response = try? JSONDecoder().decode(
                                        CreatureSpeechResponseDTO.self, from: data)
                                {
                                    logger.debug("Success!")
                                    soundFileName = response.soundFileName
                                } else {
                                    presentError(
                                        info.result
                                            ?? "The sound file job failed on the server.")
                                }
                            }
                        case .removed:
                            await MainActor.run {
                                presentError("The sound file job was removed before finishing.")
                            }
                        }
                    }

                case .failure(let error):
                    presentError("Error: \(String(describing: error.localizedDescription))")
                    logger.warning(
                        "Unable to create new sound file: \(String(describing: error.localizedDescription))"
                    )

                }

                currentAction = "idle"
            }
        } else {
            logger.warning(
                "creatureId was nil when we attempted to make a sound file for a creature?")
        }

    }

    func playSavedSound() {

        logger.debug("Attempting to play the selected sound file on the server")

        playSoundTask?.cancel()

        playSoundTask = Task {

            // Don't bother with this if the sound file isn't there
            if let sound = soundFileName {
                let result = await server.playSound(sound)
                switch result {
                case .success(let message):
                    logger.info("\(message)")
                case .failure(let error):
                    presentError("Error: \(String(describing: error.localizedDescription))")
                    logger.warning(
                        "Unable to play a sound file: \(String(describing: error.localizedDescription))"
                    )

                }
            }

        }
    }  // func playSoundOnServer

    func copySoundFileToClipboard() {
        if let soundFileName = soundFileName {
            Pasteboard.copy(soundFileName)
        }

        logger.debug("Copied filename to clipboard")
    }

    /// The alert kept its original (slightly broken) title and joke dismiss label from the
    /// hand-rolled `Alert` days — personality is a feature here.
    private func presentError(_ message: String) {
        errorAlert = ErrorAlert(title: "Unable to the list of sound files", message: message)
    }
}


#Preview {
    CreateNewCreatureSoundView()
}
