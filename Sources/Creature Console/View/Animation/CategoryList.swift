import Common
import OSLog
import SwiftUI

struct CategoryList: View {

    let server = CreatureServerClient.shared

    let creature: Creature
    @State var animationMetas: [AnimationMetadata]?
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AnimationCategory")

    @State private var errorAlert: ErrorAlert?

    @State private var loadDataTask: Task<Void, Never>? = nil

    var body: some View {
        ScrollView {
            if let metadatas = animationMetas {

                // Display each one
                ForEach(metadatas, id: \.self) { metadata in
                    AnimationDetail(animationMetadata: metadata)
                        .frame(maxWidth: .infinity)
                }

            } else {
                Text("Loading animations for \(creature.name)")
            }

        }
        .onAppear {
            logger.debug("onAppear()")
            loadData()
        }
        .onDisappear {
            loadDataTask?.cancel()
        }
        .onChange(of: creature) {
            logger.debug("onChange() in AnimationCategory")
            loadData()
        }
        .errorAlert($errorAlert, dismissLabel: "Fuck")
    }

    func loadData() {

        loadDataTask?.cancel()

        loadDataTask = Task {

            // Go load the animations
            let result = await server.listAnimations()
            logger.debug("got it")

            switch result {
            case .success(let data):
                logger.debug("success!")
                self.animationMetas = data
            case .failure(let error):
                logger.warning(
                    "Unable to load the animations for \(creature.name): \(String(describing: error.localizedDescription))"
                )
                errorAlert = ErrorAlert(
                    title: "Unable to load Animations",
                    message: "Error: \(String(describing: error.localizedDescription))"
                )
            }
        }
    }
}


#Preview {
    CategoryList(creature: .mock())
}
