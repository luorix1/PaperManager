import PDFKit
import CoreData
import OpenAI
import OSLog
import LLM

extension String: Identifiable {
    public var id: String { self }
}

class PDFProcessor {
    static let shared = PDFProcessor()
    private let logger = Logger(subsystem: "com.papermanager.app", category: "PDFProcessor")
    private var openAI: OpenAI? {
        let key = KeychainHelper.shared.getAPIKey()
        // Print only the first and last 2 chars for safety
        if let key, !key.isEmpty {
            let obfuscated = key.prefix(2) + String(repeating: "*", count: max(0, key.count-4)) + key.suffix(2)
            print("OpenAI Key in use: \(obfuscated)")
            return OpenAI(apiToken: key)
        } else {
            print("OpenAI Key in use: <none>")
        }
        return nil
    }
    
    private init() {}
    
    func processPDF(at url: URL, onError: @escaping (String) -> Void) async {
        logger.info("Starting to process PDF at: \(url.path, privacy: .public)")

        // --- Duplicate file path check ---
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Paper")
        fetchRequest.predicate = NSPredicate(format: "filePath == %@", url.path)
        fetchRequest.fetchLimit = 1
        if let count = try? context.count(for: fetchRequest), count > 0 {
            let msg = "A paper with this file is already in your library."
            logger.error("\(msg, privacy: .public)")
            await MainActor.run { onError(msg) }
            return
        }

        guard let pdf = PDFDocument(url: url) else {
            let msg = "Failed to open PDF at: \(url.path)"
            logger.error("\(msg, privacy: .public)")
            await MainActor.run { onError(msg) }
            return
        }
        
        guard let text = extractText(from: pdf) else {
            let msg = "Failed to extract text from PDF."
            logger.error("\(msg, privacy: .public)")
            await MainActor.run { onError(msg) }
            return
        }
        
        logger.debug("Successfully extracted \(text.count, privacy: .public) characters from PDF")
        
        do {
            let modelSource = ModelSourceHelper.getModelSource()
            let metadata: PaperMetadata
            if modelSource == .gptAPI {
                guard let openAI = openAI else {
                    let msg = "OpenAI API key not set."
                    logger.error("\(msg, privacy: .public)")
                    await MainActor.run { onError(msg) }
                    return
                }
                metadata = try await extractMetadata(from: text, openAI: openAI)
            } else {
                metadata = try await extractMetadataFromLocalLLM(text: text)
            }

            // --- Duplicate title check ---
            if let title = metadata.title, !title.isEmpty {
                let titleFetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Paper")
                titleFetch.predicate = NSPredicate(format: "name == %@", title)
                titleFetch.fetchLimit = 1
                if let count = try? context.count(for: titleFetch), count > 0 {
                    let msg = "A paper with the title \"\(title)\" is already in your library."
                    logger.error("\(msg, privacy: .public)")
                    await MainActor.run { onError(msg) }
                    return
                }
            }

            logger.info("Successfully extracted metadata for paper: \(metadata.title ?? "", privacy: .public)")
            
            await MainActor.run {
                savePaper(metadata: metadata, pdfPath: url.path)
            }
        } catch {
            let msg = "PDF analysis failed: \(error.localizedDescription)"
            logger.error("\(msg, privacy: .public)")
            await MainActor.run { onError(msg) }
        }
    }
    
    private func extractText(from pdf: PDFDocument) -> String? {
        guard let pdfData = pdf.string else { return nil }
        return pdfData
    }
    
    private func extractMetadata(from text: String, openAI: OpenAI) async throws -> PaperMetadata {
        let prompt = """
        Extract the following information from this academic paper text in JSON format:
        - title
        - authors (as a comma-separated string)
        - publication
        - year (as integer)
        - summary (summarize the abstract in 2-3 sentences)
        
        Text: \(text.prefix(4000))
        
        Response format (return ONLY valid JSON, no explanation or extra text):
        {
            "title": "paper title",
            "authors": "author1, author2",
            "publication": "conference or journal name",
            "year": year,
            "summary": "summary text"
        }
        """
        
        print("\n================ GPT INPUT (PROMPT) BEGIN ================\n")
        print(prompt)
        print("\n================= GPT INPUT (PROMPT) END =================\n")
        fflush(stdout)

        let systemMessage = ChatQuery.ChatCompletionMessageParam(role: .system, content: "You are a helpful assistant that extracts metadata from academic papers in JSON format.")
        let userMessage = ChatQuery.ChatCompletionMessageParam(role: .user, content: prompt)
        let messages = [systemMessage, userMessage].compactMap { $0 }
        
        let query = ChatQuery(
            messages: messages,
            model: .gpt4_o_mini
        )
        
        do {
            let result = try await openAI.chats(query: query)
            print("\n================ GPT API FULL RESULT BEGIN ================\n")
            dump(result)
            print("\n================= GPT API FULL RESULT END =================\n")
            fflush(stdout)

            if result.choices.isEmpty {
                print("GPT API returned no choices.")
                fflush(stdout)
                throw NSError(domain: "PDFProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "No choices from GPT"])
            }

            guard let jsonString = result.choices.first?.message.content else {
                print("GPT API returned no content in the first choice.")
                fflush(stdout)
                throw NSError(domain: "PDFProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "No content from GPT"])
            }
            print("\n================ GPT RAW RESPONSE BEGIN ================\n")
            print(jsonString)
            print("\n================= GPT RAW RESPONSE END =================\n")
            fflush(stdout)

            guard let jsonData = jsonString.data(using: String.Encoding.utf8) else {
                print("Failed to convert GPT response to Data.")
                fflush(stdout)
                throw NSError(domain: "PDFProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert GPT response to Data"])
            }

            do {
                let metadata = try JSONDecoder().decode(PaperMetadata.self, from: jsonData)
                return metadata
            } catch let DecodingError.valueNotFound(type, context) {
                print("DecodingError.valueNotFound: \(type), context: \(context)")
                fflush(stdout)
                // Return a fixed fallback value
                return PaperMetadata(
                    title: "Unknown",
                    authors: "Unknown",
                    publication: "Unknown",
                    year: 0,
                    summary: "No summary available"
                )
            } catch {
                print("JSON Decoding Error: \(error)")
                fflush(stdout)
                throw error
            }
        } catch {
            print("Error processing PDF: \(error)")
            fflush(stdout)
            logger.error("Error extracting metadata: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func extractMetadataFromLocalLLM(text: String) async throws -> PaperMetadata {
        guard let modelURL = LocalLLMHelper.bundledGemmaGGUFURL() else {
            throw NSError(domain: "LocalLLM", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "The bundled Gemma model could not be found. Please reinstall the app."
            ])
        }
        guard let bot = LLM(from: modelURL, template: .chatML(
            "You are a helpful assistant that extracts metadata from academic papers in JSON format."
        )) else {
            throw NSError(domain: "LocalLLM", code: 11, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize LLM from bundled GGUF."])
        }

        let prompt = """
        Extract the following information from this academic paper text in JSON format:
        - title
        - authors (as a comma-separated string)
        - publication
        - year (as integer)
        - summary (summarize the abstract in 2-3 sentences)

        Text: \(text.prefix(4000))

        Response format (return ONLY valid JSON, no explanation or extra text):
        {
            "title": "paper title",
            "authors": "author1, author2",
            "publication": "conference or journal name",
            "year": year,
            "summary": "summary text"
        }
        """

        let question = bot.preprocess(prompt, [])
        let answer = await bot.getCompletion(from: question)
        print("LLM raw output:\n\(answer)")

        // Extract JSON block if surrounded by ``` or similar
        let jsonString: String
        if let start = answer.range(of: "{"), let end = answer.range(of: "}", options: .backwards) {
            jsonString = String(answer[start.lowerBound...end.upperBound])
        } else {
            jsonString = answer
        }

        if let data = jsonString.data(using: .utf8) {
            do {
                return try JSONDecoder().decode(PaperMetadata.self, from: data)
            } catch {
                print("Decoding error: \(error)")
                print("Raw JSON: \(jsonString)")
                throw error
            }
        }
        throw NSError(domain: "LocalLLM", code: 12, userInfo: [NSLocalizedDescriptionKey: "Failed to decode model output."])
    }
    
    private func savePaper(metadata: PaperMetadata, pdfPath: String) {
        let context = PersistenceController.shared.container.viewContext
        let entity = NSEntityDescription.entity(forEntityName: "Paper", in: context)!
        let paper = NSManagedObject(entity: entity, insertInto: context)
        
        paper.setValue(UUID(), forKey: "id")
        paper.setValue(metadata.title, forKey: "name")
        paper.setValue(metadata.authors, forKey: "authors")
        paper.setValue(metadata.publication, forKey: "publication")
        paper.setValue(Int16(metadata.year ?? 0), forKey: "year")
        paper.setValue(metadata.summary, forKey: "summary")
        paper.setValue(pdfPath, forKey: "filePath")
        paper.setValue(false, forKey: "readStatus")
        
        PersistenceController.shared.save()
    }
}

struct PaperMetadata: Codable {
    let title: String?
    let authors: String?
    let publication: String?
    let year: Int?
    let summary: String?

    // Custom decoder to handle year as Int or String
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try? container.decode(String.self, forKey: .title)
        authors = try? container.decode(String.self, forKey: .authors)
        publication = try? container.decode(String.self, forKey: .publication)
        summary = try? container.decode(String.self, forKey: .summary)
        // Try to decode year as Int, then as String
        if let intYear = try? container.decode(Int.self, forKey: .year) {
            year = intYear
        } else if let strYear = try? container.decode(String.self, forKey: .year), let intYear = Int(strYear) {
            year = intYear
        } else {
            year = nil
        }
    }

    // Explicit memberwise initializer for fallback
    init(title: String?, authors: String?, publication: String?, year: Int?, summary: String?) {
        self.title = title
        self.authors = authors
        self.publication = publication
        self.year = year
        self.summary = summary
    }
} 
