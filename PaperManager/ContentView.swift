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
                    if let paperID = selectedPaperID, let paper = fetchPaper(with: paperID) {
                        PaperDetailView(paper: paper)
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
        .overlay(analyzingOverlay)
    }
    
    private func importPDF() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf]
        
        if panel.runModal() == .OK {
            guard let url = panel.url else { return }
            isAnalyzingPDF = true
            Task {
                await PDFProcessor.shared.processPDF(at: url) { msg in
                    errorMessage = msg
                    isAnalyzingPDF = false
                }
                isAnalyzingPDF = false
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
        print("[PaperListView] selectedPaperID: \(String(describing: selectedPaperID))")
        return List(selection: $selectedPaperID) {
            ForEach(filteredPapers, id: \.objectID) { paper in
                NavigationLink {
                    PaperDetailView(paper: paper)
                } label: {
                    VStack(alignment: .leading) {
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
                }
                .tag(paper.objectID)
            }
        }
    }
}

struct PaperDetailView: View {
    let paper: NSManagedObject
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
        .onAppear {
            loadPDF()
        }
        .onChange(of: paper) { _ in
            loadPDF()
        }
    }
    
    private func loadPDF() {
        if let path = paper.value(forKey: "filePath") as? String {
            pdfDocument = PDFDocument(url: URL(fileURLWithPath: path))
        } else {
            pdfDocument = nil
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
