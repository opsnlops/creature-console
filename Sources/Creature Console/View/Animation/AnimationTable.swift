import SwiftUI
import OSLog
import Common

struct AnimationTable: View {

    let eventLoop = EventLoop.shared
    var creature: Creature?

    @AppStorage("activeUniverse") var activeUniverse: UniverseIdentifier = 1

    let server = CreatureServerClient.shared
    let creatureManager = CreatureManager.shared

    @State var animations: [AnimationMetadata] = []

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AnimationTable")

    @State private var showErrorAlert = false
    @State private var alertMessage = ""
    @State private var selection: AnimationMetadata.ID? = nil

    @State private var loadDataTask: Task<Void, Never>? = nil

    var body: some View {
        VStack {
            if !animations.isEmpty {
                Table(of: AnimationMetadata.self, selection: $selection) {
                    TableColumn("Name", value: \.title)
                        .width(min: 120, ideal: 250)
                    TableColumn("Frames") { a in
                        Text(a.numberOfFrames, format: .number)
                    }
                    .width(60)
                    TableColumn("Period") { a in
                        Text("\(a.millisecondsPerFrame)ms")
                    }
                    .width(55)
                    TableColumn("Audio") { a in
                        Text(a.soundFile)
                    }
                    TableColumn("Time (ms)") { a in
                        Text(a.numberOfFrames * a.millisecondsPerFrame, format: .number)
                    }
                    .width(80)
                } rows: {
                    ForEach(animations) { metadata in
                        TableRow(metadata)
                            .contextMenu {
                                Button {
                                    print("play sound file selected")
                                } label: {
                                    Label("Play Sound File", systemImage: "music.quarternote.3")
                                }
                                .disabled(metadata.soundFile.isEmpty)

                                Button {
                                    // playAnimationLocally()
                                } label: {
                                    Label("Play Locally", systemImage: "play.fill")
                                }

                                Button {
                                    // playAnimationOnServer()
                                } label: {
                                    Label("Play on Server", systemImage: "play")
                                        .foregroundColor(.green)
                                }

                                NavigationLink(destination: AnimationEditor(), label: {
                                        Label("Edit", systemImage: "pencil")
                                            .foregroundColor(.accentColor)
                                    })
                            }
                    }
                }

                Spacer()

                // Buttons at the bottom
                HStack {
                    Button {
                        // playAnimationLocally()
                    } label: {
                        Label("Play Locally", systemImage: "play.fill")
                            .foregroundColor(.green)
                    }
                    .disabled(selection == nil)

                    Button {
                        // playAnimationOnServer()
                    } label: {
                        Label("Play on Server", systemImage: "play")
                            .foregroundColor(.blue)
                    }
                    .disabled(selection == nil)

                    NavigationLink(destination: AnimationEditor(
                        //animationId: selection,
                        ), label: {
                            Label("Edit", systemImage: "pencil")
                                .foregroundColor(.accentColor)
                        })
                    .disabled(selection == nil)
                } // Button bar HStack
                .padding()
            } else {
                ProgressView("Loading animations...")
                    .padding()
            }
        } // VStack
        .onAppear {
            logger.debug("onAppear()")
            loadData()
        }
        .onDisappear {
            loadDataTask?.cancel()
        }
        .onChange(of: selection) {
           print("selection is now \(String(describing: selection))")
        }
        .onChange(of: creature) {
            logger.info("onChange() in AnimationTable")
            loadData()
        }
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text("Unable to load Animations"),
                message: Text(alertMessage),
                dismissButton: .default(Text("Fiiiiiine"))
            )
        }
    } // body

    func loadData() {
        loadDataTask?.cancel()

        loadDataTask = Task {
            // Go load the animations
            let result = await server.listAnimations(creatureId: creature?.id)
            logger.debug("Loaded animations")

            switch result {
            case .success(let data):
                logger.debug("success!")
                self.animations = data
            case .failure(let error):
                alertMessage = "Error: \(String(describing: error.localizedDescription))"
                logger.warning("Unable to load animations: \(String(describing: error.localizedDescription))")
                showErrorAlert = true
            }
        }
    }
}

struct AnimationTable_Previews: PreviewProvider {
    static var previews: some View {
        AnimationTable(creature: .mock())
    }
}

