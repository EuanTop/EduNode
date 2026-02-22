import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit) && canImport(WebKit)
import WebKit
#endif

struct EduPresentationPreviewPayload: Identifiable {
    let id = UUID()
    let courseName: String
    let baseFileName: String
    let slides: [EduPresentationComposedSlide]
}

struct EduPresentationPreviewSheet: View {
    let payload: EduPresentationPreviewPayload

    @Environment(\.dismiss) private var dismiss

    @State private var showExporter = false
    @State private var exportDocument: EduPresentationExportDocument?
    @State private var exportContentType: UTType = .html
    @State private var exportFilename = "presentation.html"

    private var isChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    private var renderedHTML: String {
        EduPresentationHTMLExporter.printHTML(
            courseName: payload.courseName,
            slides: payload.slides,
            isChinese: isChinese
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.1).ignoresSafeArea()
                EduPresentationHTMLView(html: renderedHTML)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .padding(16)
            }
            .navigationTitle(S("app.presentation.previewTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(S("action.close")) {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(".html") {
                        exportHTML()
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

    private func exportHTML() {
        guard let data = renderedHTML.data(using: .utf8) else { return }
        presentExport(
            data: data,
            contentType: .html,
            filename: isChinese
                ? "\(payload.baseFileName)-课件.html"
                : "\(payload.baseFileName)-courseware.html"
        )
    }

    private func exportPDF() {
        guard let data = EduPresentationHTMLExporter.pdfData(
            courseName: payload.courseName,
            slides: payload.slides,
            isChinese: isChinese
        ) else { return }
        presentExport(
            data: data,
            contentType: .pdf,
            filename: isChinese
                ? "\(payload.baseFileName)-课件.pdf"
                : "\(payload.baseFileName)-courseware.pdf"
        )
    }

    private func presentExport(data: Data, contentType: UTType, filename: String) {
        exportDocument = EduPresentationExportDocument(data: data)
        exportContentType = contentType
        exportFilename = filename
        showExporter = true
    }

    private func S(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}

#if canImport(UIKit) && canImport(WebKit)
private struct EduPresentationHTMLView: UIViewRepresentable {
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
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
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
private struct EduPresentationHTMLView: View {
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

struct EduPresentationExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.html, .plainText, .pdf] }
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
