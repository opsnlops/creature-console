//
//  AudioFilePicker.swift
//  Creature Console
//
//  Created by April White on 5/10/23.
//
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers


struct AudioFilePicker: View {
    @StateObject var audioFileManager = AudioFileManager()
    
    @EnvironmentObject var audioManager: AudioManager

    @State private var importURL: URL?
    @State private var showImportSheet = false

    @State private var exportURL: URL?
    @State private var showExportSheet = false

    private var audioData = Data()
    
    var body: some View {
        VStack {


            Button("Play Audio File") {
                showImportSheet = true
            }
            .fileImporter(
                isPresented: $showImportSheet,
                allowedContentTypes: [.audio],
                onCompletion: { result in
                    do {
                        let fileURL = try result.get()
                        audioManager.play(url: fileURL)
                        
                    } catch {
                        print("Failed to play file: \(error)")
                    }
                }
            )

            
            
            Button("Import Audio File") {
                showImportSheet = true
            }
            .fileImporter(
                isPresented: $showImportSheet,
                allowedContentTypes: [.audio],
                onCompletion: { result in
                    do {
                        let fileURL = try result.get()
                        // Load the audio data
                        if let data = audioFileManager.loadFileFromiCloud(fileName: fileURL.lastPathComponent) {
                            // Do something with the audio data...
                        }
                    } catch {
                        print("Failed to import file: \(error)")
                    }
                }
            )

            Button("Export Audio File") {
                showExportSheet = true
            }
            .fileExporter(
                isPresented: $showExportSheet,
                document: Document(data: audioData),
                contentType: .audio,
                defaultFilename: "MyAudioFile.aac",
                onCompletion: { result in
                    do {
                        let fileURL = try result.get()
                        // Handle the URL of the exported file
                        print("Exported file to \(fileURL)")
                    } catch {
                        print("Failed to export file: \(error)")
                    }
                }
            )
        }
    }
}

struct Document: FileDocument {
    static var readableContentTypes: [UTType] { [.audio] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}

struct AudioFilePicker_Previews: PreviewProvider {
    static var previews: some View {
        AudioFilePicker()
    }
}
