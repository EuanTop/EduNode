import Foundation
import CryptoKit
import EduNodeContracts

public struct EduAuthenticatedSession: Sendable {
    public let userID: String
    public let email: String
    public let expiresAtUnixSeconds: Int64

    public init(
        userID: String,
        email: String,
        expiresAtUnixSeconds: Int64
    ) {
        self.userID = userID
        self.email = email
        self.expiresAtUnixSeconds = expiresAtUnixSeconds
    }
}

public enum EduServerAuthError: LocalizedError {
    case authNotConfigured
    case invalidToken
    case expiredToken
    case upstreamUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .authNotConfigured:
            return "Supabase authentication is not configured on the server."
        case .invalidToken:
            return "The Supabase access token is invalid."
        case .expiredToken:
            return "The Supabase access token has expired."
        case .upstreamUnavailable(let message):
            return message
        }
    }
}

public struct EduServerAuthManager: Sendable {
    private let configuration: EduServerSupabaseConfiguration
    private let session: URLSession
    private let cache: EduSupabaseAuthCache

    public init(
        configuration: EduServerSupabaseConfiguration,
        session: URLSession = .shared,
        cache: EduSupabaseAuthCache = EduSupabaseAuthCache()
    ) {
        self.configuration = configuration
        self.session = session
        self.cache = cache
    }

    public var isConfigured: Bool {
        configuration.isConfigured
    }

    public func validate(
        token: String,
        now: Date = .now
    ) async throws -> EduAuthenticatedSession {
        guard configuration.isConfigured,
              configuration.authBaseURL != nil else {
            throw EduServerAuthError.authNotConfigured
        }

        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw EduServerAuthError.invalidToken
        }

        let claims = decodeJWTClaims(normalizedToken)
        let nowSeconds = Int64(now.timeIntervalSince1970.rounded(.down))
        if let exp = claims?.exp, nowSeconds >= exp {
            throw EduServerAuthError.expiredToken
        }

        let tokenHash = sha256Hex(normalizedToken)
        if let cached = await cache.cachedSession(
            for: tokenHash,
            nowUnixSeconds: nowSeconds
        ) {
            return cached
        }

        let user = try await fetchUser(for: normalizedToken)
        let expiresAt = claims?.exp ?? (nowSeconds + 3600)
        let authenticated = EduAuthenticatedSession(
            userID: user.id,
            email: user.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            expiresAtUnixSeconds: expiresAt
        )

        let cacheUntil = min(expiresAt, nowSeconds + 60)
        await cache.store(
            authenticated,
            for: tokenHash,
            validUntilUnixSeconds: cacheUntil
        )
        return authenticated
    }

    public func signIn(
        email: String,
        password: String
    ) async throws -> EduBackendAuthTokenSessionResponse {
        let response: EduSupabaseSessionResponse = try await postAuthJSON(
            pathComponents: ["token"],
            queryItems: [URLQueryItem(name: "grant_type", value: "password")],
            requestBody: EduBackendAuthEmailPasswordRequest(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            ),
            responseType: EduSupabaseSessionResponse.self
        )
        return response.asTokenSessionResponse(now: .now)
    }

    public func signUp(
        email: String,
        password: String
    ) async throws -> EduBackendAuthSignUpResponse {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let response: EduSupabaseSignUpResponse = try await postAuthJSON(
            pathComponents: ["signup"],
            requestBody: EduBackendAuthEmailPasswordRequest(
                email: normalizedEmail,
                password: password
            ),
            responseType: EduSupabaseSignUpResponse.self
        )

        return EduBackendAuthSignUpResponse(
            status: response.session == nil ? "confirmation_required" : "signed_in",
            email: response.user?.email?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? normalizedEmail,
            session: response.session?.asTokenSessionResponse(now: .now)
        )
    }

    public func refresh(
        refreshToken: String
    ) async throws -> EduBackendAuthTokenSessionResponse {
        let normalizedToken = refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw EduServerAuthError.invalidToken
        }

        let response: EduSupabaseSessionResponse = try await postAuthJSON(
            pathComponents: ["token"],
            queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            requestBody: EduBackendAuthRefreshRequest(refreshToken: normalizedToken),
            responseType: EduSupabaseSessionResponse.self
        )
        return response.asTokenSessionResponse(now: .now)
    }

    public func signOut(accessToken: String) async {
        guard let baseURL = configuration.authBaseURL else { return }
        let normalizedToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else { return }

        var request = URLRequest(url: baseURL.appending(path: "logout"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.trimmedPublishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(normalizedToken)", forHTTPHeaderField: "Authorization")
        _ = try? await session.data(for: request)
    }

    public func sessionStatus(
        for accessToken: String,
        now: Date = .now
    ) async throws -> EduBackendAuthSessionStatusResponse {
        let authenticated = try await validate(token: accessToken, now: now)
        return EduBackendAuthSessionStatusResponse(
            authenticated: true,
            userID: authenticated.userID,
            email: authenticated.email,
            expiresAtUnixSeconds: authenticated.expiresAtUnixSeconds
        )
    }

    private func fetchUser(for accessToken: String) async throws -> EduSupabaseUser {
        guard let baseURL = configuration.authBaseURL else {
            throw EduServerAuthError.authNotConfigured
        }

        let url = baseURL.appending(path: "user")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.trimmedPublishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EduServerAuthError.upstreamUnavailable("Missing HTTP response from Supabase Auth.")
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw EduServerAuthError.invalidToken
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw EduServerAuthError.upstreamUnavailable(message)
        }

        do {
            return try JSONDecoder().decode(EduSupabaseUser.self, from: data)
        } catch {
            throw EduServerAuthError.upstreamUnavailable("Failed to decode Supabase user response.")
        }
    }

    private func postAuthJSON<RequestBody: Encodable, ResponseBody: Decodable>(
        pathComponents: [String],
        queryItems: [URLQueryItem] = [],
        requestBody: RequestBody,
        responseType: ResponseBody.Type
    ) async throws -> ResponseBody {
        guard var url = configuration.authBaseURL else {
            throw EduServerAuthError.authNotConfigured
        }

        for component in pathComponents {
            url.append(path: component)
        }
        if !queryItems.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = queryItems
            if let resolved = components.url {
                url = resolved
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.trimmedPublishableKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EduServerAuthError.upstreamUnavailable("Missing HTTP response from Supabase Auth.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw EduServerAuthError.upstreamUnavailable(decodedSupabaseErrorMessage(from: data, fallbackStatusCode: http.statusCode))
        }
        do {
            return try JSONDecoder().decode(responseType, from: data)
        } catch {
            throw EduServerAuthError.upstreamUnavailable("Failed to decode Supabase auth response.")
        }
    }

    private func decodedSupabaseErrorMessage(
        from data: Data,
        fallbackStatusCode: Int
    ) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["msg", "message", "error_description", "error"] {
                if let message = object[key] as? String,
                   !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return message
                }
            }
        }
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "HTTP \(fallbackStatusCode)" : raw
    }

    private func decodeJWTClaims(_ token: String) -> EduJWTClaims? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2,
              let payload = Data(base64URLEncoded: String(segments[1])) else {
            return nil
        }
        return try? JSONDecoder().decode(EduJWTClaims.self, from: payload)
    }

    private func sha256Hex(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public actor EduSupabaseAuthCache {
    private struct Entry: Sendable {
        let session: EduAuthenticatedSession
        let validUntilUnixSeconds: Int64
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    public func cachedSession(
        for tokenHash: String,
        nowUnixSeconds: Int64
    ) -> EduAuthenticatedSession? {
        guard let entry = entries[tokenHash] else { return nil }
        guard nowUnixSeconds < entry.validUntilUnixSeconds else {
            entries.removeValue(forKey: tokenHash)
            return nil
        }
        return entry.session
    }

    public func store(
        _ session: EduAuthenticatedSession,
        for tokenHash: String,
        validUntilUnixSeconds: Int64
    ) {
        entries[tokenHash] = Entry(
            session: session,
            validUntilUnixSeconds: validUntilUnixSeconds
        )
    }
}

private struct EduSupabaseUser: Decodable {
    let id: String
    let email: String?
}

private struct EduSupabaseSessionResponse: Decodable {
    let accessToken: String
    let expiresIn: Int?
    let expiresAt: Int64?
    let refreshToken: String
    let user: EduSupabaseUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case refreshToken = "refresh_token"
        case user
    }

    func asTokenSessionResponse(now: Date) -> EduBackendAuthTokenSessionResponse {
        let nowSeconds = Int64(now.timeIntervalSince1970.rounded(.down))
        let expiry = expiresAt ?? (nowSeconds + Int64(max(300, expiresIn ?? 3600)))
        return EduBackendAuthTokenSessionResponse(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userID: user.id,
            email: user.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            expiresAtUnixSeconds: expiry
        )
    }
}

private struct EduSupabaseSignUpResponse: Decodable {
    let accessToken: String?
    let expiresIn: Int?
    let expiresAt: Int64?
    let refreshToken: String?
    let user: EduSupabaseUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case refreshToken = "refresh_token"
        case user
    }

    var session: EduSupabaseSessionResponse? {
        guard let accessToken,
              let refreshToken,
              let user else {
            return nil
        }
        return EduSupabaseSessionResponse(
            accessToken: accessToken,
            expiresIn: expiresIn,
            expiresAt: expiresAt,
            refreshToken: refreshToken,
            user: user
        )
    }
}

private struct EduJWTClaims: Decodable {
    let exp: Int64?
}

private extension Data {
    init?(base64URLEncoded input: String) {
        var normalized = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        self.init(base64Encoded: normalized)
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
