import Foundation

enum EduReferenceDocumentServiceConfigError: LocalizedError {
    case backendManaged

    var errorDescription: String? {
        let isChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        switch self {
        case .backendManaged:
            return isChinese
                ? "参考教案解析现在只允许通过 EduNode backend 执行，前端不再直接读取 MinerU 配置。"
                : "Reference-document parsing is now backend-managed. The client no longer reads MinerU configuration directly."
        }
    }
}

struct EduReferenceDocumentServiceConfig {
    let apiToken: String
    let applyUploadURL: URL
    let batchResultURLPrefix: URL
    let modelVersion: String
    let language: String
    let enableFormula: Bool
    let enableTable: Bool
    let enableOCR: Bool
    let pollingIntervalNanoseconds: UInt64
    let maxPollingAttempts: Int

    static func load() throws -> EduReferenceDocumentServiceConfig {
        throw EduReferenceDocumentServiceConfigError.backendManaged
    }

    var authorizationHeaderValue: String {
        "Bearer \(apiToken)"
    }
}
