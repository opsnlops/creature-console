
import SwiftUI
import OSLog
import Common



struct LogViewView: View {
    
//    @ObservedObject var viewModel : LogViewModel
//   
//    let server : CreatureServerClient
//    @State private var logText: String = ""
//    private let textEditorId = UUID()
//    
//    private let stopFlag : StopFlag
//    private let logFilter : Server_LogFilter
//    var maxBufferSize = UserDefaults.standard.integer(forKey: "serverLogsScrollBackLines")
//    
//    private let logger : Logger
//    
//    init(server: CreatureServerClient) {
//        self.logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "LogViewView")
//        self.server = server
//        self.logFilter = Server_LogFilter.with { $0.level = .debug }
//        self.stopFlag = StopFlag()
//        
//        self.viewModel = LogViewModel(stopFlag: self.stopFlag, maxBufferSize: maxBufferSize, logFilter: self.logFilter)
//    }
    
    var body: some View {
        VStack {
            //            ScrollViewReader { scrollProxy in
            //                ScrollView {
            //                    TextEditor(text: $logText)
            //                        .font(.system(size: 14, design: .monospaced))
            //                        .frame(maxWidth: .infinity, maxHeight: .infinity)
            //                        .disabled(true) // This will prevent the user from editing the text
            //                        .id(textEditorId)
            //                        .onReceive(viewModel.$logs) { logs in
            //                            logText = logs.map { $0.description }.joined(separator: "\n")
            //                        }
            //                        .onChange(of: logText) {
            //                            scrollProxy.scrollTo(textEditorId, anchor: .bottom)
            //                        }
            //                }
            //            }
            //            HStack {
            //                Button("Start Streaming") {
            //                    Task {
            //                        logger.info("Start Streaming pressed in UI")
            //                        stopFlag.shouldStop = false
            //                        await viewModel.startStreaming(server: server, logFilter: logFilter, stopFlag: stopFlag)
            //                    }
            //                }
            //                Button("Stop Streaming") {
            //                    stopFlag.shouldStop = true
            //                    logger.info("Stop Streaming pressed in UI")
            //                }
            //            }
            //        }
            //        .onDisappear {
            //            logger.info("signalling for log streaming to stop")
            //            stopFlag.shouldStop = true

            // TODO: This is temp
            Text("Log view goes here")
        }
    }
}

