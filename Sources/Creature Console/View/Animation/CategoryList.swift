
import SwiftUI
import OSLog

struct CategoryList: View {
    
    let server = CreatureServerClient.shared

    @ObservedObject var creature: Creature
    @State var animationMetas : [AnimationMetadata]?
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AnimationCategory")
    
    @State private var showErrorAlert = false
    @State private var alertMessage = ""
    
    @State private var loadDataTask: Task<Void, Never>? = nil
    
    var body: some View {
        ScrollView {
            if let metadatas = animationMetas {
                for metadata in metadatas {
                    AnimationDetail(animationMetadata: metadata)
                        .frame(maxWidth: .infinity)
                }
                   
            }
            else {
                Text("Loading animations for \(creature.name)")
            }
               
        }
        .onAppear {
            logger.info("onAppear()")
            loadData()
        }
        .onDisappear {
            loadDataTask?.cancel()
        }
        .onChange(of: creature) {
            logger.info("onChange() in AnimationCategory")
            loadData()
        }
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text("Unable to load Animations"),
                message: Text(alertMessage),
                dismissButton: .default(Text("Fuck"))
            )
        }
    }
    
    func loadData() {
        
        loadDataTask?.cancel()
                
        loadDataTask = Task {
            // Go load the animations
            let pValue = creature.type.protobufValue
            let result = await server.listAnimations(creatureType: pValue)
            logger.debug("got it")
            
            switch(result) {
            case .success(let data):
                logger.debug("success!")
                self.animationIds = data
            case .failure(let error):
                alertMessage = "Error: \(String(describing: error.localizedDescription))"
                logger.warning("Unable to load the animations for \(creature.name): \(String(describing: error.localizedDescription))")
                showErrorAlert = true
            }
        }
    }
}


struct CategoryList_Previews: PreviewProvider {
    static var previews: some View {
        CategoryList(creature: .mock())
    }
}
