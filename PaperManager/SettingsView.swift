import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = KeychainHelper.shared.getAPIKey() ?? ""
    @State private var isObscured: Bool = true
    @State private var showSaved = false
    @State private var modelSource: ModelSource = ModelSourceHelper.getModelSource()
    @State private var localLLMPath: String = ModelSourceHelper.getLocalLLMPath() ?? ""
    @State private var selectedLocalModel: LocalLLMModel = LocalLLMHelper.getSelectedModel()
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var downloadError: Bool = false
    @State private var directoryError: String? = nil
    @State private var errorMessage: ErrorMessage? = nil
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Model Source")
                .font(.headline)
            Picker("Model Source", selection: $modelSource) {
                ForEach(ModelSource.allCases) { source in
                    Text(source.rawValue).tag(source)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: modelSource) { newValue in
                ModelSourceHelper.setModelSource(newValue)
            }

            if modelSource == .gptAPI {
                Text("OpenAI API Key")
                    .font(.headline)
                HStack {
                    if isObscured {
                        SecureField("Enter your OpenAI API Key", text: $apiKey)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    } else {
                        TextField("Enter your OpenAI API Key", text: $apiKey)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    Button(action: { isObscured.toggle() }) {
                        Image(systemName: isObscured ? "eye.slash" : "eye")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            } else {
                Text("Model: Gemma-3-4B-IT-8bit")
                    .font(.headline)
            }

            if modelSource == .localLLM {
                Text("Gemma-3-4B-IT-Q4_0 is bundled with the app and ready to use.")
                    .foregroundColor(.green)
            }

            HStack {
                Spacer()
                Button("Save") {
                    ModelSourceHelper.setModelSource(modelSource)
                    if modelSource == .gptAPI {
                        KeychainHelper.shared.saveAPIKey(apiKey)
                    } else {
                        ModelSourceHelper.setLocalLLMPath(localLLMPath)
                        LocalLLMHelper.setSelectedModel(selectedLocalModel)
                        LocalLLMHelper.setSelectedModelPath(localLLMPath)
                    }
                    showSaved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        showSaved = false
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(modelSource == .localLLM && (directoryError != nil || !LocalLLMHelper.isModelReady(selectedLocalModel)))
            }
            if showSaved {
                Text("Saved!").foregroundColor(.green)
            }
        }
        .padding()
        .frame(width: 400)
        .alert(item: $errorMessage) { error in
            Alert(
                title: Text("Error"),
                message: Text(error.message),
                dismissButton: .default(Text("OK")) { errorMessage = nil }
            )
        }
    }

    // Example PDF import trigger
    func importPDF(url: URL) {
        Task {
            await PDFProcessor.shared.processPDF(at: url) { msg in
                errorMessage = ErrorMessage(message: msg)
            }
        }
    }
} 