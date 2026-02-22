import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit) && canImport(WebKit)
import WebKit
#endif

struct EduLessonPlanPreviewPayload: Identifiable {
    let id = UUID()
    let context: EduLessonPlanContext
    let graphData: Data
    let html: String
    let baseFileName: String
}

struct EduLessonPlanPreviewSheet: View {
    let payload: EduLessonPlanPreviewPayload

    @Environment(\.dismiss) private var dismiss

    @State private var showExporter = false
    @State private var exportDocument: EduExportDocument?
    @State private var exportContentType: UTType = .plainText
    @State private var exportFilename = "lesson-plan.md"

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.1).ignoresSafeArea()
                LessonPlanHTMLView(html: payload.html)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
                    .padding(16)
            }
            .navigationTitle(S("app.export.preview.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(S("action.close")) {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(".md") {
                        exportMarkdown()
                    }
                    Button(".pdf") {
                        exportPDF()
                    }
                }
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportFilename
        ) { _ in
            exportDocument = nil
        }
    }

    private func exportMarkdown() {
        guard let data = EduLessonPlanExporter.markdownData(
            context: payload.context,
            graphData: payload.graphData
        ) else { return }
        let isChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        presentExport(
            data: data,
            contentType: .plainText,
            filename: isChinese
                ? "\(payload.baseFileName)-教案.md"
                : "\(payload.baseFileName)-lesson-plan.md"
        )
    }

    private func exportPDF() {
        guard let data = EduLessonPlanExporter.pdfData(
            context: payload.context,
            graphData: payload.graphData
        ) else { return }
        let isChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        presentExport(
            data: data,
            contentType: .pdf,
            filename: isChinese
                ? "\(payload.baseFileName)-教案.pdf"
                : "\(payload.baseFileName)-lesson-plan.pdf"
        )
    }

    private func presentExport(data: Data, contentType: UTType, filename: String) {
        exportDocument = EduExportDocument(data: data)
        exportContentType = contentType
        exportFilename = filename
        showExporter = true
    }

    private func S(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}

#if canImport(UIKit) && canImport(WebKit)
private struct LessonPlanHTMLView: UIViewRepresentable {
    let html: String

    final class Coordinator {
        var lastHTML = ""
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        webView.scrollView.backgroundColor = UIColor.clear
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        uiView.loadHTMLString(html, baseURL: nil)
    }
}
#else
private struct LessonPlanHTMLView: View {
    let html: String

    var body: some View {
        ScrollView {
            Text(html)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white)
                .padding()
        }
    }
}
#endif

struct EduExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .pdf] }
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
