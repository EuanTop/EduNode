import Foundation
#if canImport(PDFKit)
import PDFKit
#endif
import zlib

enum EduMinerUClientError: LocalizedError {
    case fileTooLarge
    case pageLimitExceeded
    case invalidResponse
    case parseFailed(String)
    case pollingTimedOut
    case missingMarkdown
    case missingZipArchive

    var errorDescription: String? {
        let isChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        switch self {
        case .fileTooLarge:
            return isChinese
                ? "参考教案 PDF 超过 10MB，当前无法处理。"
                : "The reference lesson-plan PDF is larger than 10MB and cannot be processed right now."
        case .pageLimitExceeded:
            return isChinese
                ? "参考教案 PDF 超过 20 页，当前无法处理。"
                : "The reference lesson-plan PDF exceeds 20 pages and cannot be processed right now."
        case .invalidResponse:
            return isChinese
                ? "参考教案处理结果无法识别。"
                : "The reference lesson-plan response could not be understood."
        case .parseFailed(let message):
            return message
        case .pollingTimedOut:
            return isChinese
                ? "等待参考教案处理结果超时。"
                : "Timed out while waiting for the reference lesson plan to finish processing."
        case .missingMarkdown:
            return isChinese
                ? "参考教案已读取完成，但没有提取到可用内容。"
                : "The reference lesson plan was processed, but no usable content was extracted."
        case .missingZipArchive:
            return isChinese
                ? "参考教案解析结果中没有找到可读取的压缩包。"
                : "No readable archive was found in the reference lesson-plan result."
        }
    }
}

struct EduMinerUParsedDocument: Hashable {
    let taskID: String
    let markdown: String
    let rawResultJSON: String
}

struct EduMinerUClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func parseReferencePDF(
        data: Data,
        fileName: String
    ) async throws -> EduMinerUParsedDocument {
        try validateReferencePDF(data: data)
        let config = try EduReferenceDocumentServiceConfig.load()

        let taskID = try await submitDocumentParseRequest(
            config: config,
            data: data,
            fileName: fileName
        )

        return try await pollResult(
            config: config,
            taskID: taskID
        )
    }

    private func validateReferencePDF(data: Data) throws {
        let maxBytes = 10 * 1024 * 1024
        guard data.count <= maxBytes else {
            throw EduMinerUClientError.fileTooLarge
        }

        #if canImport(PDFKit)
        if let document = PDFDocument(data: data), document.pageCount > 20 {
            throw EduMinerUClientError.pageLimitExceeded
        }
        #endif
    }

    private func submitDocumentParseRequest(
        config: EduReferenceDocumentServiceConfig,
        data: Data,
        fileName: String
    ) async throws -> String {
        var request = URLRequest(url: config.applyUploadURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        let fileItem: [String: Any] = [
            "name": fileName,
            "is_ocr": config.enableOCR,
            "data_id": UUID().uuidString
        ]
        let payload: [String: Any] = [
            "enable_formula": config.enableFormula,
            "enable_table": config.enableTable,
            "language": config.language,
            "model_version": config.modelVersion,
            "files": [fileItem]
        ]
        request.httpBody = try JSONSerialization.data(
            withJSONObject: payload,
            options: []
        )

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EduMinerUClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: responseData, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw EduMinerUClientError.parseFailed(message)
        }

        let rawObject = try JSONObject(data: responseData)
        guard let batchID = stringValue(
            in: rawObject,
            candidates: [
                ["data", "batch_id"],
                ["data", "batchId"],
                ["batch_id"],
                ["batchId"]
            ]
        ), !batchID.isEmpty,
              let uploadURLString = stringValue(
                in: rawObject,
                candidates: [
                    ["data", "file_urls", "0"],
                    ["data", "file_urls", "0", "url"],
                    ["data", "file_urls", "0", "upload_url"],
                    ["file_urls", "0"],
                    ["file_urls", "0", "url"],
                    ["file_urls", "0", "upload_url"]
                ]
              ),
              !uploadURLString.isEmpty,
              let uploadURL = URL(string: uploadURLString) else {
            let message = stringValue(
                in: rawObject,
                candidates: [["message"], ["msg"], ["detail"]]
            ) ?? (String(data: responseData, encoding: .utf8) ?? "")
            if !message.isEmpty {
                throw EduMinerUClientError.parseFailed(message)
            }
            throw EduMinerUClientError.invalidResponse
        }

        try await uploadReferencePDF(
            data: data,
            uploadURL: uploadURL
        )

        return batchID
    }

    private func uploadReferencePDF(
        data: Data,
        uploadURL: URL
    ) async throws {
        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "PUT"
        uploadRequest.timeoutInterval = 180

        let (_, uploadResponse) = try await session.upload(
            for: uploadRequest,
            from: data
        )

        guard let http = uploadResponse as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw EduMinerUClientError.invalidResponse
        }
    }

    private func pollResult(
        config: EduReferenceDocumentServiceConfig,
        taskID batchID: String
    ) async throws -> EduMinerUParsedDocument {
        var lastRawJSON = ""

        for _ in 0..<config.maxPollingAttempts {
            let url = config.batchResultURLPrefix.appending(path: batchID)
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 120
            request.setValue(config.authorizationHeaderValue, forHTTPHeaderField: "Authorization")

            let (responseData, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw EduMinerUClientError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = String(data: responseData, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                throw EduMinerUClientError.parseFailed(message)
            }

            let rawObject = try JSONObject(data: responseData)
            lastRawJSON = String(data: responseData, encoding: .utf8) ?? ""

            let state = stringValue(
                in: rawObject,
                candidates: [
                        ["data", "state"],
                        ["data", "status"],
                        ["data", "extract_result", "0", "state"],
                        ["data", "extract_result", "0", "status"],
                        ["state"],
                        ["status"]
                    ]
                )?.lowercased()

            if let state, isTerminalFailureState(state) {
                let message = stringValue(
                    in: rawObject,
                    candidates: [
                        ["data", "err_msg"],
                        ["data", "message"],
                        ["data", "msg"],
                        ["message"],
                        ["msg"],
                        ["detail"]
                    ]
                ) ?? lastRawJSON
                throw EduMinerUClientError.parseFailed(message)
            }

            if state == nil || isTerminalSuccessState(state ?? "") {
                if let markdown = try await extractMarkdown(from: rawObject) {
                    return EduMinerUParsedDocument(
                        taskID: batchID,
                        markdown: markdown,
                        rawResultJSON: lastRawJSON
                    )
                }
            }

            try await Task.sleep(nanoseconds: config.pollingIntervalNanoseconds)
        }

        throw EduMinerUClientError.pollingTimedOut
    }

    private func extractMarkdown(
        from rawObject: Any
    ) async throws -> String? {
        if let inlineMarkdown = stringValue(
            in: rawObject,
            candidates: [
                ["data", "full_md"],
                ["data", "markdown"],
                ["data", "content"],
                ["markdown"],
                ["content"]
            ]
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
           !inlineMarkdown.isEmpty {
            return inlineMarkdown
        }

        if let markdownURLString = stringValue(
            in: rawObject,
            candidates: [
                ["data", "full_md_link"],
                ["data", "full_md_url"],
                ["data", "markdown_url"],
                ["data", "md_url"],
                ["data", "result", "full_md_link"],
                ["data", "result", "full_md_url"],
                ["full_md_link"],
                ["markdown_url"]
            ]
        ), let url = URL(string: markdownURLString) {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let markdown = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !markdown.isEmpty else {
                throw EduMinerUClientError.missingMarkdown
            }
            return markdown
        }

        if let extractResults = arrayValue(
            in: rawObject,
            candidates: [
                ["data", "extract_result"],
                ["data", "extractResults"],
                ["extract_result"]
            ]
        ) {
            for item in extractResults {
                let format = stringValue(
                    in: item,
                    candidates: [["format"], ["type"], ["name"]]
                )?.lowercased() ?? ""
                if format.contains("md") || format.contains("markdown") {
                    if let inlineMarkdown = stringValue(
                        in: item,
                        candidates: [["content"], ["markdown"]]
                    )?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !inlineMarkdown.isEmpty {
                        return inlineMarkdown
                    }
                    if let urlString = stringValue(
                        in: item,
                        candidates: [["url"], ["link"], ["download_url"]]
                    ), let url = URL(string: urlString) {
                        let (data, response) = try await session.data(from: url)
                        guard let http = response as? HTTPURLResponse,
                              (200..<300).contains(http.statusCode),
                              let markdown = String(data: data, encoding: .utf8)?
                                .trimmingCharacters(in: .whitespacesAndNewlines),
                              !markdown.isEmpty else {
                            throw EduMinerUClientError.missingMarkdown
                        }
                        return markdown
                    }
                }

                if let archiveURLString = stringValue(
                    in: item,
                    candidates: [["full_zip_url"], ["zip_url"], ["archive_url"]]
                ), let archiveURL = URL(string: archiveURLString) {
                    return try await downloadMarkdownFromArchive(archiveURL)
                }
            }
        }

        if let archiveURLString = stringValue(
            in: rawObject,
            candidates: [
                ["data", "extract_result", "0", "full_zip_url"],
                ["data", "extract_result", "0", "zip_url"],
                ["data", "full_zip_url"],
                ["full_zip_url"]
            ]
        ), let archiveURL = URL(string: archiveURLString) {
            return try await downloadMarkdownFromArchive(archiveURL)
        }

        return nil
    }

    private func downloadMarkdownFromArchive(_ archiveURL: URL) async throws -> String {
        let (data, response) = try await session.data(from: archiveURL)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw EduMinerUClientError.missingZipArchive
        }
        return try extractMarkdownFromArchiveData(data)
    }

    private func extractMarkdownFromArchiveData(_ data: Data) throws -> String {
        let entries = try parseZipEntries(from: data)
        guard let target = entries.first(where: {
            let lowercased = $0.path.lowercased()
            return lowercased.hasSuffix("full.md") || lowercased.hasSuffix(".md")
        }) else {
            throw EduMinerUClientError.missingMarkdown
        }

        let extracted = try extractZipEntry(target, from: data)
        guard let markdown = String(data: extracted, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !markdown.isEmpty else {
            throw EduMinerUClientError.missingMarkdown
        }
        return markdown
    }

    private func parseZipEntries(from data: Data) throws -> [EduZIPEntry] {
        let eocdOffset = try findEndOfCentralDirectory(in: data)
        let totalEntries = Int(try readUInt16(from: data, at: eocdOffset + 10))
        var offset = Int(try readUInt32(from: data, at: eocdOffset + 16))
        var entries: [EduZIPEntry] = []
        entries.reserveCapacity(totalEntries)

        for _ in 0..<totalEntries {
            let signature = try readUInt32(from: data, at: offset)
            guard signature == 0x02014b50 else {
                throw EduMinerUClientError.missingZipArchive
            }

            let compressionMethod = try readUInt16(from: data, at: offset + 10)
            let compressedSize = Int(try readUInt32(from: data, at: offset + 20))
            let uncompressedSize = Int(try readUInt32(from: data, at: offset + 24))
            let fileNameLength = Int(try readUInt16(from: data, at: offset + 28))
            let extraLength = Int(try readUInt16(from: data, at: offset + 30))
            let commentLength = Int(try readUInt16(from: data, at: offset + 32))
            let localHeaderOffset = Int(try readUInt32(from: data, at: offset + 42))
            let nameData = try readData(
                from: data,
                range: (offset + 46)..<(offset + 46 + fileNameLength)
            )
            let path = String(data: nameData, encoding: .utf8) ?? ""

            entries.append(
                EduZIPEntry(
                    path: path,
                    compressionMethod: compressionMethod,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localHeaderOffset
                )
            )

            offset += 46 + fileNameLength + extraLength + commentLength
        }

        return entries
    }

    private func extractZipEntry(
        _ entry: EduZIPEntry,
        from archiveData: Data
    ) throws -> Data {
        let localOffset = entry.localHeaderOffset
        let signature = try readUInt32(from: archiveData, at: localOffset)
        guard signature == 0x04034b50 else {
            throw EduMinerUClientError.missingZipArchive
        }

        let fileNameLength = Int(try readUInt16(from: archiveData, at: localOffset + 26))
        let extraLength = Int(try readUInt16(from: archiveData, at: localOffset + 28))
        let dataStart = localOffset + 30 + fileNameLength + extraLength
        let compressed = try readData(
            from: archiveData,
            range: dataStart..<(dataStart + entry.compressedSize)
        )

        switch entry.compressionMethod {
        case 0:
            return compressed
        case 8:
            return try inflateRawDeflate(
                compressed,
                expectedSize: entry.uncompressedSize
            )
        default:
            throw EduMinerUClientError.missingZipArchive
        }
    }

    private func findEndOfCentralDirectory(in data: Data) throws -> Int {
        guard data.count >= 22 else {
            throw EduMinerUClientError.missingZipArchive
        }

        let lowerBound = max(0, data.count - 65_557)
        var offset = data.count - 22
        while offset >= lowerBound {
            if (try? readUInt32(from: data, at: offset)) == 0x06054b50 {
                return offset
            }
            offset -= 1
        }
        throw EduMinerUClientError.missingZipArchive
    }

    private func readUInt16(from data: Data, at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else {
            throw EduMinerUClientError.missingZipArchive
        }
        return data.withUnsafeBytes { rawBuffer in
            let pointer = rawBuffer.baseAddress!.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
            return UInt16(pointer[0]) | (UInt16(pointer[1]) << 8)
        }
    }

    private func readUInt32(from data: Data, at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else {
            throw EduMinerUClientError.missingZipArchive
        }
        return data.withUnsafeBytes { rawBuffer in
            let pointer = rawBuffer.baseAddress!.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
            return UInt32(pointer[0])
                | (UInt32(pointer[1]) << 8)
                | (UInt32(pointer[2]) << 16)
                | (UInt32(pointer[3]) << 24)
        }
    }

    private func readData(from data: Data, range: Range<Int>) throws -> Data {
        guard range.lowerBound >= 0, range.upperBound <= data.count, range.lowerBound <= range.upperBound else {
            throw EduMinerUClientError.missingZipArchive
        }
        return data.subdata(in: range)
    }

    private func inflateRawDeflate(
        _ compressedData: Data,
        expectedSize: Int
    ) throws -> Data {
        if compressedData.isEmpty {
            return Data()
        }

        var stream = z_stream()
        let windowBits = -MAX_WBITS
        let initStatus = inflateInit2_(
            &stream,
            windowBits,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else {
            throw EduMinerUClientError.missingZipArchive
        }
        defer {
            inflateEnd(&stream)
        }

        let inputSize = compressedData.count
        let outputCapacity = max(expectedSize, 64 * 1024)
        var output = Data(count: outputCapacity)
        let status: Int32 = compressedData.withUnsafeBytes { inputBuffer in
            output.withUnsafeMutableBytes { outputBuffer in
                guard let inputBase = inputBuffer.baseAddress?.assumingMemoryBound(to: Bytef.self),
                      let outputBase = outputBuffer.baseAddress?.assumingMemoryBound(to: Bytef.self) else {
                    return Z_DATA_ERROR
                }

                stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputBase)
                stream.avail_in = uInt(inputSize)
                stream.next_out = outputBase
                stream.avail_out = uInt(outputCapacity)

                return inflate(&stream, Z_FINISH)
            }
        }

        guard status == Z_STREAM_END else {
            throw EduMinerUClientError.missingZipArchive
        }

        output.count = Int(stream.total_out)
        return output
    }

    private func JSONObject(data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data, options: [])
    }

    private func object(at path: [String], in rawObject: Any) -> Any? {
        path.reduce(Optional(rawObject)) { current, key in
            if let dictionary = current as? [String: Any] {
                return dictionary[key]
            }
            if let array = current as? [Any], let index = Int(key), array.indices.contains(index) {
                return array[index]
            }
            return nil
        }
    }

    private func stringValue(
        in rawObject: Any,
        candidates: [[String]]
    ) -> String? {
        for path in candidates {
            if let value = object(at: path, in: rawObject) as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private func arrayValue(
        in rawObject: Any,
        candidates: [[String]]
    ) -> [Any]? {
        for path in candidates {
            if let value = object(at: path, in: rawObject) as? [Any] {
                return value
            }
        }
        return nil
    }

    private func isTerminalSuccessState(_ state: String) -> Bool {
        [
            "done", "success", "succeeded", "completed", "finished"
        ].contains(state)
    }

    private func isTerminalFailureState(_ state: String) -> Bool {
        [
            "failed", "error", "cancelled", "canceled"
        ].contains(state)
    }
}

private struct EduZIPEntry {
    let path: String
    let compressionMethod: UInt16
    let compressedSize: Int
    let uncompressedSize: Int
    let localHeaderOffset: Int
}
