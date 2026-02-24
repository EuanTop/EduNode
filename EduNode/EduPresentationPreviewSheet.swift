import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit) && canImport(WebKit)
import WebKit
#endif
#if canImport(PDFKit)
import PDFKit
#endif

struct EduPresentationPreviewPayload: Identifiable {
    let id = UUID()
    let courseName: String
    let baseFileName: String
    let slides: [EduPresentationComposedSlide]
    let pageStyle: PresentationPageStyle
    let textTheme: PresentationTextTheme
    let overlayHTMLBySlideID: [UUID: String]
}

struct EduPresentationPreviewSheet: View {
    let payload: EduPresentationPreviewPayload

    @Environment(\.dismiss) private var dismiss

    @State private var showExporter = false
    @State private var exportDocument: EduPresentationExportDocument?
    @State private var exportContentType: UTType = .html
    @State private var exportFilename = "presentation.html"
    @State private var isExportingPDF = false
    @State private var cachedPDFHash: Int?
    @State private var cachedPDFData: Data?

    private var isChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    private var renderedHTML: String {
        themedPresentationDeckHTML(
            courseName: payload.courseName,
            slides: payload.slides,
            isChinese: isChinese,
            pageStyle: payload.pageStyle,
            textTheme: payload.textTheme,
            overlayHTMLBySlideID: payload.overlayHTMLBySlideID
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.1).ignoresSafeArea()
                Group {
                    #if canImport(UIKit) && canImport(WebKit)
                    EduPresentationHTMLView(html: renderedHTML)
                    #else
                    EduPresentationHTMLView(html: renderedHTML)
                    #endif
                }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
            .navigationTitle(S("app.presentation.previewTitle"))
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

    private func exportHTML() {
        guard !isExportingPDF else { return }
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
        guard !isExportingPDF else { return }
        let filename = isChinese
            ? "\(payload.baseFileName)-课件.pdf"
            : "\(payload.baseFileName)-courseware.pdf"
        let title = payload.courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (isChinese ? "课程演讲" : "Course Presentation")
            : payload.courseName
        let html = renderedHTML
        let exportHash = html.hashValue ^ title.hashValue
        if cachedPDFHash == exportHash, let cachedPDFData {
            presentExport(
                data: cachedPDFData,
                contentType: .pdf,
                filename: filename
            )
            return
        }
        isExportingPDF = true
        Task(priority: .userInitiated) {
            let perSlideData = await exportPerSlidePDFData(title: title)
            let data: Data?
            if let perSlideData {
                data = perSlideData
            } else {
                data = await EduPresentationHTMLExporter.pdfDataAsync(
                    markupHTML: html,
                    title: title
                )
            }
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

    private func presentExport(data: Data, contentType: UTType, filename: String) {
        exportDocument = EduPresentationExportDocument(data: data)
        exportContentType = contentType
        exportFilename = filename
        showExporter = true
    }

    private func exportPerSlidePDFData(title: String) async -> Data? {
        guard !payload.slides.isEmpty else { return nil }
        var pageDataList: [Data] = []
        pageDataList.reserveCapacity(payload.slides.count)

        for slide in payload.slides {
            let overlayHTML: [UUID: String]
            if let overlay = payload.overlayHTMLBySlideID[slide.id], !overlay.isEmpty {
                overlayHTML = [slide.id: overlay]
            } else {
                overlayHTML = [:]
            }
            let singleSlideHTML = themedPresentationDeckHTML(
                courseName: payload.courseName,
                slides: [slide],
                isChinese: isChinese,
                pageStyle: payload.pageStyle,
                textTheme: payload.textTheme,
                overlayHTMLBySlideID: overlayHTML
            )
            let pdfHTML = singleSlidePDFHTML(from: singleSlideHTML)
            guard let pagePDF = await EduPresentationHTMLExporter.pdfDataAsync(
                markupHTML: pdfHTML,
                title: title
            ) else {
                return nil
            }
            pageDataList.append(pagePDF)
        }

        return mergedPDFData(from: pageDataList)
    }

    private func singleSlidePDFHTML(from html: String) -> String {
        let pdfOverrideCSS = """
        <style id="edunode-pdf-override">
          html, body {
            width: 100% !important;
            height: 100% !important;
            margin: 0 !important;
            padding: 0 !important;
            overflow: hidden !important;
            background: #ffffff !important;
          }
          body.preview, body.interactive, body.embedded {
            padding: 0 !important;
            overflow: hidden !important;
            background: #ffffff !important;
          }
          .deck {
            width: 100% !important;
            height: 100% !important;
            min-height: 100% !important;
            display: block !important;
            padding: 0 !important;
            gap: 0 !important;
          }
          .slide {
            width: 100% !important;
            height: 100% !important;
            min-height: 100% !important;
            margin: 0 !important;
            padding: 0 !important;
            display: flex !important;
            position: relative !important;
            inset: auto !important;
            page-break-after: auto !important;
          }
          .slide-sheet {
            width: 100% !important;
            max-width: none !important;
            min-height: 100% !important;
            height: 100% !important;
            aspect-ratio: auto !important;
            margin: 0 !important;
            border: none !important;
            border-radius: 0 !important;
            box-shadow: none !important;
          }
          .controls { display: none !important; }
        </style>
        """

        guard let headClose = html.range(of: "</head>") else {
            return html
        }
        return html.replacingCharacters(in: headClose.lowerBound..<headClose.lowerBound, with: pdfOverrideCSS + "\n")
    }

    private func mergedPDFData(from pageDataList: [Data]) -> Data? {
        #if canImport(PDFKit)
        let document = PDFDocument()
        var insertIndex = 0
        for pageData in pageDataList {
            guard let pageDocument = PDFDocument(data: pageData) else { continue }
            for index in 0..<pageDocument.pageCount {
                guard let page = pageDocument.page(at: index) else { continue }
                document.insert(page, at: insertIndex)
                insertIndex += 1
            }
        }
        guard insertIndex > 0 else { return nil }
        return document.dataRepresentation()
        #else
        return pageDataList.first
        #endif
    }

    private func S(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    private var exportActions: some View {
        HStack(spacing: 0) {
            exportActionButton(title: ".html", action: exportHTML)
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
