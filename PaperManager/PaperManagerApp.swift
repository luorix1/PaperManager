import SwiftUI

@main
struct PaperManagerApp: App {
    let persistenceController = PersistenceController.shared
    @State private var showSettings = false
    @State private var modelSource: ModelSource = ModelSourceHelper.getModelSource()
    @State private var localLLMPath: String = ModelSourceHelper.getLocalLLMPath() ?? ""
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .sheet(isPresented: $showSettings, onDismiss: {
                    modelSource = ModelSourceHelper.getModelSource()
                }) {
                    SettingsView()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import PDF...") {
                    importPDF()
                }
                .keyboardShortcut("i", modifiers: [.command])
            }
            CommandMenu("Settings") {
                Button("Model Settings...") {
                    showSettings = true
                }
            }
        }
    }
    
    private func importPDF() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf]
        
        if panel.runModal() == .OK {
            guard let url = panel.url else { return }
            // Handle PDF import - will be implemented in PDFProcessor
            Task {
                await PDFProcessor.shared.processPDF(at: url, onError: { errorMsg in
                    print("PDF Processing Error: \(errorMsg)")
                })
            }
        }
    }
} 
