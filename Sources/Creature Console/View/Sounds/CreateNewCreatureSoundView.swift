import Common
import Foundation
import OSLog
import SwiftUI

struct CreateNewCreatureSoundView: View {

    let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "CreateNewCreatureSoundView")

    let server = CreatureServerClient.shared

    @State private var creatureCacheState = CreatureCacheState(creatures: [:], empty: true)

    @State private var showErrorAlert = false
    @State private var alertMessage = ""


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
                            ForEach(creatureCacheState.creatures.keys.sorted(), id: \.self) { id in
                                Text(creatureCacheState.creatures[id]?.name ?? "Unknown").tag(
                                    id as CreatureIdentifier?)
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
        .task {
            for await state in await CreatureCache.shared.stateUpdates {
                await MainActor.run {
                    creatureCacheState = state
                }
            }
        }
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text("Unable to the list of sound files"),
                message: Text(alertMessage),
                dismissButton: .default(Text("No Music for Us"))
            )
        }
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

                DispatchQueue.main.async {
                    currentAction = "saving"
                }

                let saveResult = await server.createCreatureSpeechSoundFile(
                    creatureId: creatureId, title: title, text: text)

                switch saveResult {
                case .success(let result):
                    logger.debug("Success!")

                    DispatchQueue.main.async {
                        soundFileName = result.soundFileName
                    }

                case .failure(let error):
                    alertMessage = "Error: \(String(describing: error.localizedDescription))"
                    logger.warning(
                        "Unable to create new sound file: \(String(describing: error.localizedDescription))"
                    )
                    showErrorAlert = true

                }

                DispatchQueue.main.async {
                    currentAction = "idle"
                }
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
                    print(message)
                case .failure(let error):
                    DispatchQueue.main.async {
                        alertMessage = "Error: \(String(describing: error.localizedDescription))"
                        logger.warning(
                            "Unable to play a sound file: \(String(describing: error.localizedDescription))"
                        )
                        showErrorAlert = true
                    }

                }
            }

        }
    }  // func playSoundOnServer

    func copySoundFileToClipboard() {
        #if os(iOS)
            if let soundFileName = soundFileName {
                UIPasteboard.general.string = soundFileName
            }
        #elseif os(macOS)
            if let soundFileName = soundFileName {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(soundFileName, forType: .string)
            }
        #endif

        logger.info("Copied filename to clipboard")
    }
}


#Preview {
    CreateNewCreatureSoundView()
}
