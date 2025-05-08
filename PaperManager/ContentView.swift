import SwiftUI
import CoreData
import PDFKit
import AppKit

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var filterType: FilterType = .name
    @State private var selectedPaperID: NSManagedObjectID? = nil {
        didSet {
            print("[ContentView] selectedPaperID changed: \(String(describing: selectedPaperID))")
        }
    }
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: ErrorMessage? = nil
    @State private var isAnalyzingPDF = false
    @State private var showDeletePrompt = false
    @State private var originalPDFPath: String?
    @State private var copiedPDFPath: String?
    @State private var pendingDeleteURL: URL?
    @State private var analyzingCount: Int = 0
    @State private var appMode: AppMode = .list
    
    enum FilterType: String, CaseIterable {
        case name = "Name"
        case authors = "Authors"
        case publication = "Publication"
        case year = "Year"
        case text = "Text Search"
    }
    
    enum AppMode: String, CaseIterable {
        case list = "List"
        case table = "Table"
        // FIXME: Chat mode temporarily disabled
        // Will be re-implemented in the future if users require it
        // case chat = "Chat"
    }
    
    private var analyzingOverlay: some View {
        Group {
            if isAnalyzingPDF {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("Analyzing PDF...")
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
                        .shadow(radius: 10)
                }
            }
        }
    }

    var body: some View {
        Group {
            switch appMode {
            case .list:
                NavigationSplitView {
                    PaperListView(searchText: $searchText, 
                                debouncedSearchText: $debouncedSearchText,
                                filterType: $filterType, 
                                selectedPaperID: $selectedPaperID)
                } detail: {
                    if let paperID = selectedPaperID {
                        PaperDetailView(paperID: paperID)
                    } else {
                        Text("Select a paper")
                    }
                }
            case .table:
                DatabaseView()
            // FIXME: Chat mode temporarily disabled
            // Will be re-implemented in the future if users require it
            /*
            case .chat:
                ChatModeView()
            */
            }
        }
        .navigationTitle("Paper Manager")
        .toolbar {
            ToolbarItem {
                Picker("Mode", selection: $appMode) {
                    ForEach(AppMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            ToolbarItem {
                Button(action: importPDF) {
                    Label("Import PDF", systemImage: "doc.badge.plus")
                }
            }
            ToolbarItem {
                Button(action: { 
                    print("[ContentView] Delete button pressed. selectedPaperID: \(String(describing: selectedPaperID))")
                    showDeleteConfirmation = true 
                }) {
                    Label("Delete Paper", systemImage: "trash")
                }
                .disabled(selectedPaperID == nil)
            }
            ToolbarItem {
                Menu {
                    ForEach(FilterType.allCases, id: \.self) { type in
                        Button(type.rawValue) {
                            filterType = type
                        }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Filter by \(filterType.rawValue)")
        .onChange(of: searchText) { newValue in
            // Debounce the search text changes
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms delay
                await MainActor.run {
                    debouncedSearchText = newValue
                }
            }
        }
        .alert("Are you sure you want to delete this paper?", isPresented: $showDeleteConfirmation, presenting: selectedPaperID) { paperID in
            Button("Yes", role: .destructive) {
                if let paper = fetchPaper(with: paperID) {
                    deletePaper(paper)
                }
            }
            Button("No", role: .cancel) {}
        } message: { _ in
            Text("This action cannot be undone.")
        }
        .alert(item: $errorMessage) { msg in
            Alert(
                title: Text("Error"),
                message: Text(msg.message),
                dismissButton: .default(Text("OK")) { errorMessage = nil }
            )
        }
        .alert(isPresented: $showDeletePrompt) {
            Alert(
                title: Text("PDF Imported"),
                message: Text("""
                    The PDF has been copied to:
                    \(copiedPDFPath ?? "")

                    Original file:
                    \(originalPDFPath ?? "")

                    Do you want to delete the original file to save space?
                    """),
                primaryButton: .destructive(Text("Delete Original")) {
                    if let url = pendingDeleteURL {
                        try? FileManager.default.removeItem(at: url)
                    }
                },
                secondaryButton: .cancel(Text("Keep Both"))
            )
        }
        .overlay(alignment: .topTrailing) {
            if analyzingCount > 0 {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Analyzing \(analyzingCount) PDF\(analyzingCount > 1 ? "s" : "")...")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
                .padding(10)
                .background(.ultraThinMaterial)
                .cornerRadius(10)
                .shadow(radius: 4)
                .padding(.top, 8)
                .padding(.trailing, 16)
            }
        }
    }
    
    private func importPDF() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf]
        
        if panel.runModal() == .OK {
            let urls = panel.urls
            if !urls.isEmpty {
                analyzingCount += urls.count
                Task {
                    await processBatchPDFs(urls: urls)
                }
            }
        }
    }
    
    private func processBatchPDFs(urls: [URL]) async {
        for url in urls {
            await copyAndProcessPDF(originalURL: url)
        }
    }
    
    private func copyAndProcessPDF(originalURL: URL) async {
        // Copy PDF to app folder first
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let appFolderURL = documentsURL.appendingPathComponent("PaperManager")
        if !fileManager.fileExists(atPath: appFolderURL.path) {
            try? fileManager.createDirectory(at: appFolderURL, withIntermediateDirectories: true, attributes: nil)
        }
        let targetURL = appFolderURL.appendingPathComponent(originalURL.lastPathComponent)
        do {
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.copyItem(at: originalURL, to: targetURL)
            print("[copyAndProcessPDF] Copied file to: \(targetURL.path)")
        } catch {
            print("[copyAndProcessPDF] Error copying PDF: \(error)")
            DispatchQueue.main.async {
                self.errorMessage = ErrorMessage(message: "Failed to copy PDF: \(error.localizedDescription)")
                self.analyzingCount = max(0, self.analyzingCount - 1)
            }
            return
        }
        
        // Now process the PDF at the copied location
        var didError = false
        await PDFProcessor.shared.processPDF(at: targetURL, onError: { msg in
            DispatchQueue.main.async {
                self.errorMessage = ErrorMessage(message: msg)
                print("[copyAndProcessPDF] Error: \(msg)")
                didError = true
                self.analyzingCount = max(0, self.analyzingCount - 1)
            }
        })
        // If no error, show prompt to delete original
        if !didError {
            DispatchQueue.main.async {
                print("[copyAndProcessPDF] Success, showing delete prompt")
                self.originalPDFPath = originalURL.path
                self.copiedPDFPath = targetURL.path
                self.pendingDeleteURL = originalURL
                self.showDeletePrompt = true
                self.analyzingCount = max(0, self.analyzingCount - 1)
            }
        }
    }
    
    private func deletePaper(_ paper: NSManagedObject) {
        withAnimation {
            viewContext.delete(paper)
            try? viewContext.save()
        }
        selectedPaperID = nil
    }
    
    private func fetchPaper(with id: NSManagedObjectID) -> NSManagedObject? {
        try? viewContext.existingObject(with: id)
    }
}

struct PaperListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var searchText: String
    @Binding var debouncedSearchText: String
    @Binding var filterType: ContentView.FilterType
    @Binding var selectedPaperID: NSManagedObjectID?
    
    @FetchRequest(
        entity: NSEntityDescription.entity(forEntityName: "Paper", in: PersistenceController.shared.container.viewContext)!,
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)],
        animation: .default)
    private var papers: FetchedResults<NSManagedObject>
    
    var filteredPapers: [NSManagedObject] {
        guard !debouncedSearchText.isEmpty else { return Array(papers) }
        
        return papers.filter { paper in
            switch filterType {
            case .name:
                return (paper.value(forKey: "name") as? String)?.localizedCaseInsensitiveContains(debouncedSearchText) ?? false
            case .authors:
                return (paper.value(forKey: "authors") as? String)?.localizedCaseInsensitiveContains(debouncedSearchText) ?? false
            case .publication:
                return (paper.value(forKey: "publication") as? String)?.localizedCaseInsensitiveContains(debouncedSearchText) ?? false
            case .year:
                guard let yearStr = Int16(debouncedSearchText) else { return false }
                return (paper.value(forKey: "year") as? Int16) == yearStr
            case .text:
                guard let filePath = paper.value(forKey: "filePath") as? String,
                      let pdfDocument = PDFDocument(url: URL(fileURLWithPath: filePath)) else {
                    return false
                }
                // Search through the PDF content
                let searchString = debouncedSearchText.lowercased()
                for i in 0..<pdfDocument.pageCount {
                    if let page = pdfDocument.page(at: i),
                       let pageText = page.string?.lowercased(),
                       pageText.contains(searchString) {
                        return true
                    }
                }
                return false
            }
        }
    }
    
    var body: some View {
        if let selectedPaperID = selectedPaperID,
           let selectedPaper = try? viewContext.existingObject(with: selectedPaperID),
           let uuid = selectedPaper.value(forKey: "id") as? UUID {
            print("[PaperListView] selectedPaperID: \(uuid.uuidString)")
        } else {
            print("[PaperListView] selectedPaperID: nil")
        }
        return List {
            ForEach(filteredPapers, id: \.objectID) { paper in
                let isSelected = selectedPaperID == paper.objectID
                Button(action: {
                    if isSelected {
                        selectedPaperID = nil
                    } else {
                        let newID = paper.objectID
                        selectedPaperID = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            selectedPaperID = newID
                        }
                    }
                }) {
                    VStack(alignment: .leading) {
                        if let uuid = paper.value(forKey: "id") as? UUID {
                            Text(uuid.uuidString)
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        HStack {
                            Text(paper.value(forKey: "name") as? String ?? "Untitled")
                                .font(.headline)
                            if filterType == .text && !debouncedSearchText.isEmpty {
                                Image(systemName: "text.magnifyingglass")
                                    .foregroundColor(.blue)
                            }
                        }
                        Text(paper.value(forKey: "authors") as? String ?? "Unknown authors")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if let publication = paper.value(forKey: "publication") as? String {
                            Text(publication)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

struct PaperDetailView: View {
    let paperID: NSManagedObjectID
    @Environment(\.managedObjectContext) private var viewContext
    @State private var paper: NSManagedObject?
    @State private var pdfDocument: PDFDocument?
    @State private var currentMatchIndex: Int = 0
    @State private var totalMatches: Int = 0
    @State private var searchText: String = ""
    
    var body: some View {
        VStack {
            if let pdfDocument = pdfDocument {
                HStack {
                    TextField("Search in PDF...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 200)
                    
                    if totalMatches > 0 {
                        Text("\(currentMatchIndex + 1) of \(totalMatches)")
                            .foregroundColor(.secondary)
                        
                        Button(action: { 
                            currentMatchIndex = (currentMatchIndex - 1 + totalMatches) % totalMatches 
                        }) {
                            Image(systemName: "chevron.up")
                        }
                        .disabled(totalMatches == 0)
                        
                        Button(action: { 
                            currentMatchIndex = (currentMatchIndex + 1) % totalMatches 
                        }) {
                            Image(systemName: "chevron.down")
                        }
                        .disabled(totalMatches == 0)
                    }
                }
                .padding(.horizontal)
                
                PDFKitView(
                    document: pdfDocument,
                    searchText: searchText,
                    currentMatchIndex: $currentMatchIndex,
                    totalMatches: $totalMatches
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("PDF not found")
                    .foregroundColor(.secondary)
            }
        }
        .onAppear(perform: loadPaper)
        .onChange(of: paperID) { _ in
            loadPaper()
        }
        .onChange(of: searchText) { _ in
            currentMatchIndex = 0
        }
    }
    
    private func loadPaper() {
        if let fetchedPaper = try? viewContext.existingObject(with: paperID),
           let path = fetchedPaper.value(forKey: "filePath") as? String {
            self.paper = fetchedPaper
            self.pdfDocument = PDFDocument(url: URL(fileURLWithPath: path))
        } else {
            self.paper = nil
            self.pdfDocument = nil
        }
    }
}

struct PDFKitView: NSViewRepresentable {
    typealias NSViewType = PDFView

    let document: PDFDocument
    let searchText: String
    @Binding var currentMatchIndex: Int
    @Binding var totalMatches: Int
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.minScaleFactor = 1.0
        pdfView.maxScaleFactor = 4.0
        pdfView.scaleFactor = 1.0
        
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = document
        
        // Clear all highlight annotations from all pages
        for i in 0..<document.pageCount {
            if let page = document.page(at: i) {
                let highlights = page.annotations.filter { $0.annotationKeyValues[PDFAnnotationKey.subtype] as? String == PDFAnnotationSubtype.highlight.rawValue || $0.type == PDFAnnotationSubtype.highlight.rawValue }
                for annotation in highlights {
                    page.removeAnnotation(annotation)
                }
            }
        }
        
        // If there's search text, highlight all matches
        if !searchText.isEmpty {
            let searchString = searchText.lowercased()
            var matches: [PDFSelection] = []
            
            // Search through all pages
            for i in 0..<document.pageCount {
                if let page = document.page(at: i) {
                    let selections = document.findString(searchString, withOptions: [])
                    for selection in selections {
                        // Create a highlight annotation for each match
                        let bounds = selection.bounds(for: page)
                        
                        // Safety check for valid bounds
                        guard bounds.width > 0 && bounds.height > 0,
                              !bounds.isInfinite,
                              !bounds.origin.x.isNaN && !bounds.origin.y.isNaN &&
                              !bounds.width.isNaN && !bounds.height.isNaN else {
                            continue
                        }
                        
                        // Ensure bounds are within page bounds
                        let pageBounds = page.bounds(for: .mediaBox)
                        let safeBounds = CGRect(
                            x: max(0, min(bounds.minX, pageBounds.width)),
                            y: max(0, min(bounds.minY, pageBounds.height)),
                            width: min(bounds.width, pageBounds.width - bounds.minX),
                            height: min(bounds.height, pageBounds.height - bounds.minY)
                        )
                        
                        matches.append(selection)
                    }
                }
            }
            
            totalMatches = matches.count
            
            // Add highlights: yellow for all, orange for current
            for (idx, selection) in matches.enumerated() {
                for page in selection.pages {
                    let bounds = selection.bounds(for: page)
                    // Safety check for valid bounds
                    guard bounds.width > 0 && bounds.height > 0,
                          !bounds.isInfinite,
                          !bounds.origin.x.isNaN && !bounds.origin.y.isNaN &&
                          !bounds.width.isNaN && !bounds.height.isNaN else {
                        continue
                    }
                    let pageBounds = page.bounds(for: .mediaBox)
                    let safeBounds = CGRect(
                        x: max(0, min(bounds.minX, pageBounds.width)),
                        y: max(0, min(bounds.minY, pageBounds.height)),
                        width: min(bounds.width, pageBounds.width - bounds.minX),
                        height: min(bounds.height, pageBounds.height - bounds.minY)
                    )
                    let highlight = PDFAnnotation(bounds: safeBounds, forType: .highlight, withProperties: nil)
                    highlight.color = (idx == currentMatchIndex) ? NSColor.orange : NSColor.yellow
                    page.addAnnotation(highlight)
                }
            }
            
            // Navigate to the current match
            if !matches.isEmpty && currentMatchIndex < matches.count {
                let selection = matches[currentMatchIndex]
                if let page = selection.pages.first {
                    nsView.go(to: page)
                    nsView.go(to: selection)
                }
            }
        } else {
            totalMatches = 0
            currentMatchIndex = 0
        }
    }
}

struct DatabaseView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        entity: NSEntityDescription.entity(forEntityName: "Paper", in: PersistenceController.shared.container.viewContext)!,
        sortDescriptors: [NSSortDescriptor(key: "id", ascending: true)],
        animation: .default)
    private var papers: FetchedResults<NSManagedObject>

    let columns: [(title: String, key: String, width: CGFloat, monospaced: Bool)] = [
        ("id", "id", 180, true),
        ("name", "name", 180, false),
        ("authors", "authors", 180, false),
        ("publication", "publication", 180, false),
        ("year", "year", 80, false),
        ("filePath", "filePath", 260, false)
    ]

    @State private var selectedPaper: NSManagedObject? = nil

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(spacing: 0) {
                // Header
                LazyHStack(spacing: 0) {
                    ForEach(columns, id: \.key) { col in
                        cellHeader(col.title, width: col.width, monospaced: col.monospaced)
                    }
                }
                .background(Color.gray.opacity(0.25))
                // Rows
                ForEach(Array(papers.enumerated()), id: \.element.objectID) { (index, paper) in
                    LazyHStack(spacing: 0) {
                        ForEach(columns, id: \.key) { col in
                            let value: String = {
                                if col.key == "year" {
                                    if let y = paper.value(forKey: "year") as? Int16 { return String(y) } else { return "" }
                                } else if col.key == "id" {
                                    return String(describing: paper.value(forKey: col.key) ?? "")
                                } else {
                                    return paper.value(forKey: col.key) as? String ?? ""
                                }
                            }()
                            cellText(
                                value,
                                width: col.width,
                                monospaced: col.monospaced
                            )
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedPaper = paper
                    }
                    .background(index % 2 == 0 ? Color(NSColor.controlBackgroundColor) : Color(NSColor.windowBackgroundColor))
                }
            }
            .padding()
        }
        if let paper = selectedPaper {
            Divider().padding(.vertical, 8)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(allPaperFields(paper: paper), id: \.0) { (label, value) in
                        HStack(alignment: .top) {
                            Text("\(label):").bold().frame(width: 100, alignment: .topLeading)
                            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                .padding([.horizontal, .bottom])
            }
        }
    }

    private func allPaperFields(paper: NSManagedObject) -> [(String, String)] {
        let fields = [
            ("id", String(describing: paper.value(forKey: "id") ?? "")),
            ("name", paper.value(forKey: "name") as? String ?? ""),
            ("authors", paper.value(forKey: "authors") as? String ?? ""),
            ("publication", paper.value(forKey: "publication") as? String ?? ""),
            ("year", { if let y = paper.value(forKey: "year") as? Int16 { return String(y) } else { return "" } }()),
            ("filePath", paper.value(forKey: "filePath") as? String ?? ""),
            ("summary", paper.value(forKey: "summary") as? String ?? "")
        ]
        return fields
    }

    @ViewBuilder
    private func cellHeader(_ text: String, width: CGFloat, monospaced: Bool = false) -> some View {
        ZStack {
            Rectangle()
                .stroke(Color.gray.opacity(0.7), lineWidth: 1)
            Text(text)
                .bold()
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .frame(minWidth: width, maxWidth: width, minHeight: 28, maxHeight: 28, alignment: .leading)
                .padding(.horizontal, 4)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .background(Color.gray.opacity(0.25))
    }

    @ViewBuilder
    private func cellText(_ text: String, width: CGFloat, monospaced: Bool = false) -> some View {
        ZStack {
            Rectangle()
                .stroke(Color.gray.opacity(0.4), lineWidth: 1)
            Text(text)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .frame(minWidth: width, maxWidth: width, minHeight: 24, maxHeight: 24, alignment: .leading)
                .padding(.horizontal, 4)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

struct ChatModeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var query: String = ""
    @State private var chatHistory: [(String, [NSManagedObject])] = []
    @State private var isSearching = false

    var body: some View {
        VStack {
            HStack {
                Text("Chat Mode").font(.title2).bold()
                Spacer()
                Button("Clear History") {
                    chatHistory.removeAll()
                }
                .disabled(chatHistory.isEmpty)
            }
            .padding(.bottom, 4)
            Divider()
            ScrollView {
                ForEach(Array(chatHistory.enumerated()), id: \.offset) { idx, entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("You: \(entry.0)").bold()
                            Spacer()
                            Button(action: { chatHistory.remove(at: idx) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        if entry.1.isEmpty {
                            Text("No matching papers found.").italic()
                        } else {
                            ForEach(entry.1, id: \.objectID) { paper in
                                Text(paper.value(forKey: "name") as? String ?? "Untitled")
                                    .font(.headline)
                                Text(paper.value(forKey: "summary") as? String ?? "")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Divider()
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            Divider()
            HStack {
                TextField("Ask about your papers...", text: $query)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disabled(isSearching)
                Button("Send") {
                    Task { await runQuery() }
                }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
            }
            .padding()
        }
        .padding()
    }

    func runQuery() async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        // Generate embedding for query
        let queryEmbedding: [Float]
        do {
            queryEmbedding = try await PDFProcessor.shared.generateEmbedding(for: query)
        } catch {
            chatHistory.append((query, []))
            query = ""
            return
        }
        // Fetch all papers with embeddings
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Paper")
        fetchRequest.predicate = NSPredicate(format: "embedding != nil")
        let papers = (try? viewContext.fetch(fetchRequest)) ?? []
        // Compute similarity
        let scored = papers.compactMap { paper -> (NSManagedObject, Float)? in
            guard let data = paper.value(forKey: "embedding") as? Data else { return nil }
            let count = data.count / MemoryLayout<Float>.size
            let arr = data.withUnsafeBytes { ptr in
                Array(UnsafeBufferPointer<Float>(start: ptr.baseAddress!.assumingMemoryBound(to: Float.self), count: count))
            }
            guard arr.count == queryEmbedding.count else { return nil }
            let sim = cosineSimilarity(arr, queryEmbedding)
            return (paper, sim)
        }
        let topPapers = scored.sorted { $0.1 > $1.1 }.prefix(3).map { $0.0 }
        chatHistory.append((query, Array(topPapers)))
        query = ""
    }

    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        let dot = zip(a, b).map(*).reduce(0, +)
        let normA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let normB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        return dot / (normA * normB + 1e-8)
    }
} 
