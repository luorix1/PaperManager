import Foundation

enum ModelSource: String, CaseIterable, Identifiable {
    case gptAPI = "GPT API"
    case localLLM = "Local LLM"
    var id: String { rawValue }
}

class ModelSourceHelper {
    static let sourceKey = "model_source"
    static let localLLMPathKey = "local_llm_path"

    static func getModelSource() -> ModelSource {
        if let raw = UserDefaults.standard.string(forKey: sourceKey),
           let source = ModelSource(rawValue: raw) {
            return source
        }
        return .gptAPI
    }

    static func setModelSource(_ source: ModelSource) {
        UserDefaults.standard.set(source.rawValue, forKey: sourceKey)
    }

    static func getLocalLLMPath() -> String? {
        UserDefaults.standard.string(forKey: localLLMPathKey)
    }

    static func setLocalLLMPath(_ path: String) {
        UserDefaults.standard.set(path, forKey: localLLMPathKey)
    }
} 