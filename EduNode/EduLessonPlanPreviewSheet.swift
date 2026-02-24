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
    @State private var isExportingPDF = false
    @State private var cachedPDFHash: Int?
    @State private var cachedPDFData: Data?

    private var isChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.1).ignoresSafeArea()
                Group {
                    #if canImport(UIKit) && canImport(WebKit)
                    LessonPlanHTMLView(html: payload.html)
                    #else
                    LessonPlanHTMLView(html: payload.html)
                    #endif
                }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
                    .padding(16)
                if isExportingPDF {
                    ZStack {
                        Color.black.opacity(0.32)
                            .ignoresSafeArea()
                        VStack(spacing: 10) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                            Text(isChinese ? "正在生成 PDF…" : "Generating PDF…")
                                .font(.callout)
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .transition(.opacity)
                }
            }
            .navigationTitle(S("app.export.preview.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(S("action.close")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    exportActions
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
        guard !isExportingPDF else { return }
        guard let data = EduLessonPlanExporter.markdownData(
            context: payload.context,
            graphData: payload.graphData
        ) else { return }
        presentExport(
            data: data,
            contentType: .plainText,
            filename: isChinese
                ? "\(payload.baseFileName)-教案.md"
                : "\(payload.baseFileName)-lesson-plan.md"
        )
    }

    private func exportPDF() {
        guard !isExportingPDF else { return }
        let filename = isChinese
            ? "\(payload.baseFileName)-教案.pdf"
            : "\(payload.baseFileName)-lesson-plan.pdf"
        let context = payload.context
        let graphData = payload.graphData
        let exportHash = payload.html.hashValue ^ context.name.hashValue
        if cachedPDFHash == exportHash, let cachedPDFData {
            presentExport(
                data: cachedPDFData,
                contentType: .pdf,
                filename: filename
            )
            return
        }
        isExportingPDF = true
        Task.detached(priority: .userInitiated) {
            let data = await MainActor.run {
                EduLessonPlanExporter.pdfData(
                    context: context,
                    graphData: graphData
                )
            }
            await MainActor.run {
                isExportingPDF = false
                guard let data else { return }
                cachedPDFHash = exportHash
                cachedPDFData = data
                presentExport(
                    data: data,
                    contentType: .pdf,
                    filename: filename
                )
            }
        }
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

    private var exportActions: some View {
        HStack(spacing: 0) {
            exportActionButton(title: ".md", action: exportMarkdown)
            Rectangle()
                .fill(Color.white.opacity(0.32))
                .frame(width: 1, height: 16)
                .padding(.horizontal, 4)
            exportActionButton(title: ".pdf", action: exportPDF)
        }
        .disabled(isExportingPDF)
    }

    private func exportActionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .opacity(isExportingPDF ? 0.6 : 1)
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
