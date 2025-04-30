import SwiftUI

struct SettingsView: View {
    @State private var localLLMPath: String = ""
    @State private var selectedLocalModel: LocalLLMModel?

    var body: some View {
        VStack {
            Text("Model Settings")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.bottom, 20)

            HStack {
                TextField("Path to model directory", text: $localLLMPath)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Browse") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.directoryURL = URL(fileURLWithPath: LocalLLMHelper.getSelectedModelPath() ?? "")
                    if panel.runModal() == .OK, let url = panel.url {
                        localLLMPath = url.path
                        LocalLLMHelper.setSelectedModelPath(localLLMPath)
                    }
                }
            }

            if !localLLMPath.isEmpty && !FileManager.default.fileExists(atPath: localLLMPath, isDirectory: nil) {
                Text("Directory does not exist at the selected path.").foregroundColor(.red)
            }

            if LocalLLMHelper.isModelReady(selectedLocalModel) {
                Text("Model directory selected: \(URL(fileURLWithPath: localLLMPath).lastPathComponent)")
                    .foregroundColor(.green)
            }

            Spacer()
        }
        .padding()
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
} 