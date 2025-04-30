import Foundation

enum LocalLLMModel: String, CaseIterable, Identifiable {
    case gemma3 = "Gemma-3-4B-IT-8bit"
    case mistral = "Mistral-7B-Instruct-v0.2"
    case olmoe = "OLMoE-1B-7B-0125-Instruct"
    case deepseek = "deepseek-vl2-small-4bit"

    var id: String { rawValue }

    var huggingFacePageURL: URL? {
        switch self {
        case .gemma3:
            return URL(string: "https://huggingface.co/mlx-community/gemma-3-4b-it-8bit")
        case .mistral:
            return URL(string: "https://huggingface.co/mlx-community/Mistral-7B-Instruct-v0.2")
        case .olmoe:
            return URL(string: "https://huggingface.co/mlx-community/OLMoE-1B-7B-0125-Instruct")
        case .deepseek:
            return URL(string: "https://huggingface.co/mlx-community/deepseek-vl2-small-4bit")
        }
    }

    var description: String {
        switch self {
        case .gemma3:
            return """
            **Gemma-3-4B-IT-8bit**  
            - Download: [mlx-community/gemma-3-4b-it-8bit](https://huggingface.co/mlx-community/gemma-3-4b-it-8bit)
            - Setup:
                pip install huggingface_hub hf_transfer
                export HF_HUB_ENABLE_HF_TRANSFER=1
                huggingface-cli download --local-dir gemma-3-4b-it-8bit mlx-community/gemma-3-4b-it-8bit
            """
        case .mistral:
            return """
            **Mistral-7B-Instruct-v0.2**  
            - Download: [mlx-community/Mistral-7B-Instruct-v0.2](https://huggingface.co/mlx-community/Mistral-7B-Instruct-v0.2)
            - Setup:
                pip install huggingface_hub hf_transfer
                export HF_HUB_ENABLE_HF_TRANSFER=1
                huggingface-cli download --local-dir-use-symlinks False --local-dir mlx_model mlx-community/Mistral-7B-Instruct-v0.2
            """
        case .olmoe:
            return """
            **OLMoE-1B-7B-0125-Instruct**  
            - Download: [mlx-community/OLMoE-1B-7B-0125-Instruct](https://huggingface.co/mlx-community/OLMoE-1B-7B-0125-Instruct)
            - Setup:
                pip install huggingface_hub hf_transfer
                export HF_HUB_ENABLE_HF_TRANSFER=1
                huggingface-cli download --local-dir OLMoE-1B-7B-0125-Instruct mlx-community/OLMoE-1B-7B-0125-Instruct
            """
        case .deepseek:
            return """
            **deepseek-vl2-small-4bit**  
            - Download: [mlx-community/deepseek-vl2-small-4bit](https://huggingface.co/mlx-community/deepseek-vl2-small-4bit)
            - Setup:
                pip install huggingface_hub hf_transfer
                export HF_HUB_ENABLE_HF_TRANSFER=1
                huggingface-cli download --local-dir deepseek-vl2-small-4bit mlx-community/deepseek-vl2-small-4bit
            """
        }
    }

    /// The expected MLX model directory name (for user guidance)
    var mlxModelName: String {
        switch self {
        case .gemma3: return "gemma-3-4b-it-8bit"
        case .mistral: return "mistral-7b"
        case .olmoe: return "olmoe-1b-7b-0125-instruct"
        case .deepseek: return "deepseek-vl2-small-4bit"
        }
    }

    // MARK: – system prompt
    var systemPrompt: String {
        "You are a helpful assistant that extracts metadata from academic papers in JSON format."
    }
}

class LocalLLMHelper {
    static let selectedModelKey = "local_llm_selected_model"
    static let selectedModelPathKey = "local_llm_selected_model_path"

    static func getSelectedModel() -> LocalLLMModel {
        if let raw = UserDefaults.standard.string(forKey: selectedModelKey),
           let model = LocalLLMModel(rawValue: raw) {
            return model
        }
        return .gemma3
    }

    static func setSelectedModel(_ model: LocalLLMModel) {
        UserDefaults.standard.set(model.rawValue, forKey: selectedModelKey)
    }

    static func getSelectedModelPath() -> String? {
        UserDefaults.standard.string(forKey: selectedModelPathKey)
    }

    static func setSelectedModelPath(_ path: String) {
        UserDefaults.standard.set(path, forKey: selectedModelPathKey)
    }

    /// Checks if the selected path is a directory and contains a model file
    static func isModelReady(_ model: LocalLLMModel) -> Bool {
        guard let path = getSelectedModelPath(), !path.isEmpty else { return false }
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        if !exists || !isDir.boolValue { return false }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        return files.contains { $0.hasSuffix(".safetensors") || $0.hasSuffix(".gguf") }
    }

    static func bundledGemmaGGUFURL() -> URL? {
        Bundle.main.url(forResource: "gemma-3-4b-it-Q4_0", withExtension: "gguf")
    }
} 