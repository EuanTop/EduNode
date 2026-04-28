import Foundation
import Security

extension Notification.Name {
    static let eduNodeBackendSessionDidChange = Notification.Name("edunode.backend.session.didChange")
}

struct EduBackendSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let userID: String
    let email: String
    let expiresAtUnixSeconds: Int64

    var needsRefresh: Bool {
        Int64(Date().timeIntervalSince1970.rounded(.down)) >= (expiresAtUnixSeconds - 60)
    }
}

enum EduBackendSessionStore {
    private static let service = "com.euan.edunode.backend"
    private static let sessionAccount = "server_session"
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedSession: EduBackendSession?

    static func load() -> EduBackendSession? {
        cacheLock.lock()
        let cached = cachedSession
        cacheLock.unlock()
        if let cached {
            return cached
        }

        if let session = loadFromKeychain() {
            cacheLock.lock()
            cachedSession = session
            cacheLock.unlock()
            return session
        }

        return nil
    }

    static func save(_ session: EduBackendSession) {
        cacheLock.lock()
        cachedSession = session
        cacheLock.unlock()

        guard let data = try? JSONEncoder().encode(session),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        let status = EduBackendKeychainStore.save(json, service: service, account: sessionAccount)
        if status != errSecSuccess {
            print("[EduNode][Auth] Keychain save failed status=\(status)")
        }
        NotificationCenter.default.post(name: .eduNodeBackendSessionDidChange, object: nil)
    }

    static func clear() {
        cacheLock.lock()
        cachedSession = nil
        cacheLock.unlock()

        let status = EduBackendKeychainStore.delete(service: service, account: sessionAccount)
        if status != errSecSuccess && status != errSecItemNotFound {
            print("[EduNode][Auth] Keychain delete failed status=\(status)")
        }
        EduBackendRuntimeStatusStore.clear()
        NotificationCenter.default.post(name: .eduNodeBackendSessionDidChange, object: nil)
    }

    static var currentAccessToken: String? {
        guard let session = load() else { return nil }
        let token = session.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    private static func loadFromKeychain() -> EduBackendSession? {
        guard let raw = EduBackendKeychainStore.load(service: service, account: sessionAccount),
              let data = raw.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(EduBackendSession.self, from: data)
    }

}

enum EduBackendRuntimeStatusStore {
    private static let defaults = UserDefaults.standard
    private static let recordKey = "edunode.backend.runtime.status.v1"

    static func save(_ status: EduAgentRuntimeStatusResponse) {
        guard let data = try? JSONEncoder().encode(status) else { return }
        defaults.set(data, forKey: recordKey)
    }

    static func load() -> EduAgentRuntimeStatusResponse? {
        guard let data = defaults.data(forKey: recordKey) else { return nil }
        return try? JSONDecoder().decode(EduAgentRuntimeStatusResponse.self, from: data)
    }

    static func clear() {
        defaults.removeObject(forKey: recordKey)
    }
}

enum EduBackendAuthError: LocalizedError {
    case backendNotConfigured
    case authenticationRequired
    case refreshRequired
    case requestFailed(String)
    case invalidResponse

    var errorDescription: String? {
        let isChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        switch self {
        case .backendNotConfigured:
            return isChinese ? "当前应用尚未连接 EduNode 在线服务。" : "The app is not connected to EduNode online service yet."
        case .authenticationRequired:
            return isChinese ? "请先登录 EduNode 账户。" : "Please sign in to your EduNode account first."
        case .refreshRequired:
            return isChinese ? "账户登录态已失效，请重新登录。" : "The account session expired. Please sign in again."
        case .requestFailed(let message):
            return message
        case .invalidResponse:
            return isChinese ? "后端鉴权返回无法解析。" : "The backend auth response could not be decoded."
        }
    }
}

struct EduBackendAuthService {
    let backendConfig: EduBackendServiceConfig
    private let session: URLSession

    init?(
        backendConfig: EduBackendServiceConfig? = EduBackendServiceConfig.loadOptional(),
        session: URLSession = .shared
    ) {
        guard let backendConfig else { return nil }
        self.backendConfig = backendConfig
        self.session = session
    }

    func signIn(
        email: String,
        password: String
    ) async throws -> EduBackendSession {
        let response: EduBackendAuthTokenSessionResponse = try await postJSON(
            path: ["auth", "sign-in"],
            accessToken: nil,
            requestBody: EduBackendAuthEmailPasswordRequest(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            ),
            responseType: EduBackendAuthTokenSessionResponse.self
        )
        let session = response.asBackendSession
        EduBackendSessionStore.save(session)
        return session
    }

    func signUp(
        email: String,
        password: String
    ) async throws -> EduBackendSignUpResult {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let response: EduBackendAuthSignUpResponse = try await postJSON(
            path: ["auth", "sign-up"],
            accessToken: nil,
            requestBody: EduBackendAuthEmailPasswordRequest(
                email: normalizedEmail,
                password: password
            ),
            responseType: EduBackendAuthSignUpResponse.self
        )

        if let sessionPayload = response.session,
           response.status == "signed_in" {
            let session = sessionPayload.asBackendSession
            EduBackendSessionStore.save(session)
            return .signedIn(session)
        }

        return .confirmationRequired(email: response.email.nonEmpty ?? normalizedEmail)
    }

    func signOutCurrentSession() async {
        let currentAccessToken = EduBackendSessionStore.currentAccessToken
        if let currentAccessToken, !currentAccessToken.isEmpty {
            _ = try? await postEmpty(
                path: ["auth", "sign-out"],
                accessToken: currentAccessToken
            )
        }
        EduBackendSessionStore.clear()
    }

    func currentSessionStatus() async throws -> EduBackendAuthSessionStatusResponse {
        let current = try await ensureValidSession()
        return try await getJSON(
            path: ["auth", "session"],
            accessToken: current.accessToken,
            responseType: EduBackendAuthSessionStatusResponse.self
        )
    }

    func ensureValidSession() async throws -> EduBackendSession {
        try await EduBackendSessionCoordinator.shared.ensureValidSession(using: self)
    }

    func forceRefreshStoredSession() async throws -> EduBackendSession {
        guard let current = EduBackendSessionStore.load() else {
            throw EduBackendAuthError.authenticationRequired
        }

        do {
            return try await refresh(session: current)
        } catch let authError as EduBackendAuthError {
            switch authError {
            case .authenticationRequired, .refreshRequired:
                EduBackendSessionStore.clear()
            case .backendNotConfigured, .requestFailed, .invalidResponse:
                break
            }
            throw authError
        } catch {
            throw EduBackendAuthError.requestFailed(error.localizedDescription)
        }
    }

    fileprivate func refresh(session current: EduBackendSession) async throws -> EduBackendSession {
        let normalizedRefreshToken = current.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRefreshToken.isEmpty else {
            EduBackendSessionStore.clear()
            throw EduBackendAuthError.refreshRequired
        }

        let response: EduBackendAuthTokenSessionResponse = try await postJSON(
            path: ["auth", "refresh"],
            accessToken: nil,
            requestBody: EduBackendAuthRefreshRequest(refreshToken: normalizedRefreshToken),
            responseType: EduBackendAuthTokenSessionResponse.self
        )
        let refreshed = response.asBackendSession
        EduBackendSessionStore.save(refreshed)
        return refreshed
    }

    private func getJSON<ResponseBody: Decodable>(
        path: [String],
        accessToken: String?,
        responseType: ResponseBody.Type
    ) async throws -> ResponseBody {
        let request = makeRequest(
            path: path,
            method: "GET",
            accessToken: accessToken,
            body: nil,
            timeout: 45
        )
        let data = try await send(request)
        do {
            return try JSONDecoder().decode(responseType, from: data)
        } catch {
            throw EduBackendAuthError.invalidResponse
        }
    }

    private func postJSON<RequestBody: Encodable, ResponseBody: Decodable>(
        path: [String],
        accessToken: String?,
        requestBody: RequestBody,
        responseType: ResponseBody.Type
    ) async throws -> ResponseBody {
        let body = try JSONEncoder().encode(requestBody)
        let request = makeRequest(
            path: path,
            method: "POST",
            accessToken: accessToken,
            body: body,
            timeout: 60
        )
        let data = try await send(request)
        do {
            return try JSONDecoder().decode(responseType, from: data)
        } catch {
            throw EduBackendAuthError.invalidResponse
        }
    }

    private func postEmpty(
        path: [String],
        accessToken: String?
    ) async throws -> Data {
        let request = makeRequest(
            path: path,
            method: "POST",
            accessToken: accessToken,
            body: nil,
            timeout: 30
        )
        return try await send(request)
    }

    private func makeRequest(
        path: [String],
        method: String,
        accessToken: String?,
        body: Data?,
        timeout: TimeInterval
    ) -> URLRequest {
        var url = backendConfig.baseURL
        for component in path {
            url.append(path: component)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken, !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EduBackendAuthError.requestFailed("Missing HTTP response from EduNode backend.")
        }

        if http.statusCode == 401 {
            throw EduBackendAuthError.refreshRequired
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = decodedBackendErrorMessage(from: data)
            throw EduBackendAuthError.requestFailed(message.isEmpty ? "HTTP \(http.statusCode)" : message)
        }

        return data
    }

    private func decodedBackendErrorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["reason", "message", "error_description", "error"] {
                if let message = object[key] as? String,
                   !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return message
                }
            }
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

actor EduBackendSessionCoordinator {
    static let shared = EduBackendSessionCoordinator()

    private var refreshTask: Task<EduBackendSession, Error>?

    func ensureValidSession(using service: EduBackendAuthService) async throws -> EduBackendSession {
        guard let current = await MainActor.run(body: {
            EduBackendSessionStore.load()
        }) else {
            throw EduBackendAuthError.authenticationRequired
        }
        let shouldRefresh = await MainActor.run(body: {
            current.needsRefresh
        })
        if !shouldRefresh {
            return current
        }
        if let refreshTask {
            return try await refreshTask.value
        }

        let task = Task {
            try await service.refresh(session: current)
        }
        refreshTask = task
        defer { refreshTask = nil }

        do {
            return try await task.value
        } catch {
            if let authError = error as? EduBackendAuthError {
                switch authError {
                case .authenticationRequired, .refreshRequired:
                    await MainActor.run(body: {
                        EduBackendSessionStore.clear()
                    })
                case .backendNotConfigured, .requestFailed, .invalidResponse:
                    break
                }
                throw authError
            }
            throw EduBackendAuthError.requestFailed(error.localizedDescription)
        }
    }
}

enum EduBackendSignUpResult: Equatable {
    case signedIn(EduBackendSession)
    case confirmationRequired(email: String)
}

private enum EduBackendKeychainStore {
    @discardableResult
    static func save(_ value: String, service: String, account: String) -> OSStatus {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        let payload: [String: Any] = query.merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]) { _, new in new }
        return SecItemAdd(payload as CFDictionary, nil)
    }

    static func load(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(service: String, account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        return SecItemDelete(query as CFDictionary)
    }
}

private extension EduBackendAuthTokenSessionResponse {
    var asBackendSession: EduBackendSession {
        EduBackendSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userID: userID,
            email: email,
            expiresAtUnixSeconds: expiresAtUnixSeconds
        )
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
