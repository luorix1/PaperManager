import SwiftUI
import CoreData
import PDFKit
import AppKit

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var searchText = ""
    @State private var filterType: FilterType = .name
    @State private var selectedPaperID: NSManagedObjectID? = nil {
        didSet {
            print("[ContentView] selectedPaperID changed: \(String(describing: selectedPaperID))")
        }
    }
    @State private var showDeleteConfirmation = false
    @State private var showDatabaseView = false
    @State private var errorMessage: String? = nil
    @State private var isAnalyzingPDF = false
    @State private var showDeletePrompt = false
    @State private var originalPDFPath: String?
    @State private var copiedPDFPath: String?
    @State private var pendingDeleteURL: URL?
    @State private var analyzingCount: Int = 0
    
    enum FilterType: String, CaseIterable {
        case name = "Name"
        case authors = "Authors"
        case publication = "Publication"
        case year = "Year"
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
            if showDatabaseView {
                DatabaseView()
            } else {
                NavigationSplitView {
                    PaperListView(searchText: $searchText, filterType: $filterType, selectedPaperID: $selectedPaperID)
                } detail: {
                    if let paperID = selectedPaperID {
                        PaperDetailView(paperID: paperID)
                    } else {
                        Text("Select a paper")
                    }
                }
            }
        }
        .navigationTitle("Paper Manager")
        .toolbar {
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
                Button(action: { showDatabaseView.toggle() }) {
                    Label("Database View", systemImage: "tablecells")
                }
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
                message: Text(msg),
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
                self.errorMessage = "Failed to copy PDF: \(error.localizedDescription)"
                self.analyzingCount = max(0, self.analyzingCount - 1)
            }
            return
        }
        
        // Now process the PDF at the copied location
        var didError = false
        await PDFProcessor.shared.processPDF(at: targetURL, onError: { msg in
            DispatchQueue.main.async {
                self.errorMessage = msg
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
    @Binding var filterType: ContentView.FilterType
    @Binding var selectedPaperID: NSManagedObjectID?
    
    @FetchRequest(
        entity: NSEntityDescription.entity(forEntityName: "Paper", in: PersistenceController.shared.container.viewContext)!,
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)],
        animation: .default)
    private var papers: FetchedResults<NSManagedObject>
    
    var filteredPapers: [NSManagedObject] {
        guard !searchText.isEmpty else { return Array(papers) }
        
        return papers.filter { paper in
            switch filterType {
            case .name:
                return (paper.value(forKey: "name") as? String)?.localizedCaseInsensitiveContains(searchText) ?? false
            case .authors:
                return (paper.value(forKey: "authors") as? String)?.localizedCaseInsensitiveContains(searchText) ?? false
            case .publication:
                return (paper.value(forKey: "publication") as? String)?.localizedCaseInsensitiveContains(searchText) ?? false
            case .year:
                guard let yearStr = Int16(searchText) else { return false }
                return (paper.value(forKey: "year") as? Int16) == yearStr
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
                        Text(paper.value(forKey: "name") as? String ?? "Untitled")
                            .font(.headline)
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

    var body: some View {
        VStack {
            if let pdfDocument = pdfDocument {
                PDFKitView(document: pdfDocument)
            } else {
                Text("PDF not found")
                    .foregroundColor(.secondary)
            }
        }
        .onAppear(perform: loadPaper)
        .onChange(of: paperID) { _ in
            loadPaper()
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

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = document
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
