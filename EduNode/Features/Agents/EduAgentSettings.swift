import Foundation
import SwiftUI
import Security
import CryptoKit

struct EduAgentProviderSettings: Equatable {
    var providerName: String = "OpenAI-Compatible"
    var baseURLString: String = "https://api.openai.com/v1"
    var model: String = "gpt-4.1"
    var apiKey: String = ""
    var temperature: Double = 0.35
    var maxTokens: Int = 3200
    var timeoutSeconds: Double = 90
    var additionalSystemPrompt: String = ""

    var trimmedBaseURLString: String {
        baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isConfigured: Bool {
        !trimmedBaseURLString.isEmpty && !trimmedModel.isEmpty && !trimmedAPIKey.isEmpty
    }
}

enum EduAgentSettingsStore {
    private static let defaults = UserDefaults.standard
    private static let service = "com.euan.edunode.agent"
    private static let accountAPIKey = "openai_compatible_api_key"
    private static let providerNameKey = "edunode.agent.provider_name"
    private static let baseURLKey = "edunode.agent.base_url"
    private static let modelKey = "edunode.agent.model"
    private static let temperatureKey = "edunode.agent.temperature"
    private static let maxTokensKey = "edunode.agent.max_tokens"
    private static let timeoutKey = "edunode.agent.timeout"
    private static let additionalPromptKey = "edunode.agent.additional_prompt"

    static func load() -> EduAgentProviderSettings {
        EduAgentProviderSettings(
            providerName: value(for: providerNameKey, fallback: "OpenAI-Compatible"),
            baseURLString: value(for: baseURLKey, fallback: "https://api.openai.com/v1"),
            model: value(for: modelKey, fallback: "gpt-4.1"),
            apiKey: loadAPIKey(),
            temperature: clamped(
                defaults.object(forKey: temperatureKey) as? Double ?? 0.35,
                min: 0,
                max: 2
            ),
            maxTokens: max(256, defaults.object(forKey: maxTokensKey) as? Int ?? 3200),
            timeoutSeconds: clamped(
                defaults.object(forKey: timeoutKey) as? Double ?? 90,
                min: 15,
                max: 600
            ),
            additionalSystemPrompt: value(for: additionalPromptKey, fallback: "")
        )
    }

    static func save(_ settings: EduAgentProviderSettings) {
        defaults.set(settings.providerName, forKey: providerNameKey)
        defaults.set(settings.trimmedBaseURLString, forKey: baseURLKey)
        defaults.set(settings.trimmedModel, forKey: modelKey)
        defaults.set(clamped(settings.temperature, min: 0, max: 2), forKey: temperatureKey)
        defaults.set(max(256, settings.maxTokens), forKey: maxTokensKey)
        defaults.set(clamped(settings.timeoutSeconds, min: 15, max: 600), forKey: timeoutKey)
        defaults.set(settings.additionalSystemPrompt, forKey: additionalPromptKey)
        saveAPIKey(settings.trimmedAPIKey)
    }

    static func loadAPIKey() -> String {
        KeychainStore.load(service: service, account: accountAPIKey) ?? ""
    }

    private static func saveAPIKey(_ key: String) {
        if key.isEmpty {
            KeychainStore.delete(service: service, account: accountAPIKey)
        } else {
            KeychainStore.save(key, service: service, account: accountAPIKey)
        }
    }

    private static func value(for key: String, fallback: String) -> String {
        let raw = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? fallback : raw
    }

    private static func clamped(_ value: Double, min lower: Double, max upper: Double) -> Double {
        Swift.max(lower, Swift.min(upper, value))
    }
}

private enum EduAgentProviderPreset: CaseIterable {
    case openAICompatible
    case claudeCompatible

    func providerName(isChinese: Bool) -> String {
        switch self {
        case .openAICompatible:
            return "OpenAI-Compatible"
        case .claudeCompatible:
            return "Claude-Compatible"
        }
    }

    var baseURL: String {
        switch self {
        case .openAICompatible:
            return "https://api.openai.com/v1"
        case .claudeCompatible:
            return "https://www.right.codes/claude/v1/messages"
        }
    }

    var model: String {
        switch self {
        case .openAICompatible:
            return "gpt-4.1"
        case .claudeCompatible:
            return "claude-3-5-sonnet-latest"
        }
    }

    func title(isChinese: Bool) -> String {
        switch self {
        case .openAICompatible:
            return "OpenAI-Compatible"
        case .claudeCompatible:
            return "Claude-Compatible"
        }
    }
}

struct EduAgentConnectionValidationRecord: Codable, Equatable {
    let signature: String
    let testedAt: Date
    let isReachable: Bool
    let message: String
}

enum EduAgentConnectionStatusStore {
    private static let defaults = UserDefaults.standard
    private static let recordKey = "edunode.agent.connection.validation_record.v1"

    static func status(for settings: EduAgentProviderSettings) -> EduAgentConnectionValidationRecord? {
        guard settings.isConfigured else { return nil }
        guard let data = defaults.data(forKey: recordKey),
              let record = try? JSONDecoder().decode(EduAgentConnectionValidationRecord.self, from: data),
              record.signature == signature(for: settings) else {
            return nil
        }
        return record
    }

    static func saveResult(
        isReachable: Bool,
        message: String,
        for settings: EduAgentProviderSettings
    ) {
        guard settings.isConfigured else {
            defaults.removeObject(forKey: recordKey)
            return
        }

        let record = EduAgentConnectionValidationRecord(
            signature: signature(for: settings),
            testedAt: .now,
            isReachable: isReachable,
            message: message
        )
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: recordKey)
        }
    }

    private static func signature(for settings: EduAgentProviderSettings) -> String {
        let raw = [
            settings.providerName,
            settings.trimmedBaseURLString,
            settings.trimmedModel,
            settings.trimmedAPIKey
        ].joined(separator: "\n")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private enum KeychainStore {
    static func save(_ value: String, service: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        let payload: [String: Any] = query.merging([
            kSecValueData as String: data
        ]) { _, new in new }
        SecItemAdd(payload as CFDictionary, nil)
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

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct EduAgentSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var currentSession: EduBackendSession?
    @State private var isAuthenticating = false
    @State private var lastError: String?
    @State private var infoMessage: String?

    let onSaved: (() -> Void)?
    let allowsContinueWithoutAccount: Bool
    let onContinueWithoutAccount: (() -> Void)?

    init(
        onSaved: (() -> Void)? = nil,
        allowsContinueWithoutAccount: Bool = false,
        onContinueWithoutAccount: (() -> Void)? = nil
    ) {
        self.onSaved = onSaved
        self.allowsContinueWithoutAccount = allowsContinueWithoutAccount
        self.onContinueWithoutAccount = onContinueWithoutAccount
    }

    private var isChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    private var backendConfiguration: EduBackendServiceConfig? {
        EduBackendServiceConfig.loadOptional()
    }

    var body: some View {
        Group {
            if allowsContinueWithoutAccount {
                startupGateBody
            } else {
                accountSheetBody
            }
        }
        .preferredColorScheme(.dark)
        .task {
            hydrateSession()
        }
        .onDisappear {
            clearDraftCredentials()
        }
    }

    private var accountSheetBody: some View {
        NavigationStack {
            ScrollView {
                contentStack
                    .padding(20)
            }
            .background(Color(white: 0.08).ignoresSafeArea())
            .navigationTitle(isChinese ? "账户" : "Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isChinese ? "关闭" : "Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var startupGateBody: some View {
        ZStack {
            Color(white: 0.08)
                .ignoresSafeArea()

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: max(geometry.size.height * 0.16, 56))

                        contentStack
                            .frame(maxWidth: 560)
                            .frame(maxWidth: .infinity)

                        Spacer(minLength: max(geometry.size.height * 0.18, 72))
                    }
                    .frame(minHeight: geometry.size.height)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: 12) {
            if allowsContinueWithoutAccount {
                welcomeHeaderSection
            }
            statusBanner
            accountCard
            if allowsContinueWithoutAccount && currentSession == nil {
                continueWithoutAccountButton
            }
        }
    }

    private var welcomeHeaderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isChinese ? "登录 EduNode" : "Sign In to EduNode")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            Text(
                isChinese
                ? "登录后即可使用 AI 搭图、教案生成与参考文档解析。若暂时不登录，也可以先进入工作区继续使用节点画布、文档与导出功能。"
                : "Sign in to unlock AI-assisted canvas building, lesson-plan generation, and reference-template parsing. You can also continue without an account and still use the canvas, documentation, and exports."
            )
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.88))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let lastError, !lastError.isEmpty {
            messageCard(
                title: isChinese ? "登录失败" : "Sign-In Failed",
                message: lastError,
                tint: .orange
            )
        } else if let infoMessage, !infoMessage.isEmpty {
            messageCard(
                title: isChinese ? "提示" : "Notice",
                message: infoMessage,
                tint: .blue
            )
        } else if !accountServicesAvailable {
            messageCard(
                title: isChinese ? "在线账户暂不可用" : "Online Account Unavailable",
                message: isChinese
                    ? "当前构建尚未接入在线账户服务。你仍然可以先使用节点画布、文档与导出功能；AI 与参考文档解析会在登录能力接通后启用。"
                    : "This build is not configured with an EduNode backend yet. You can still use the canvas, documentation, and exports first; AI and reference parsing will become available once sign-in is connected.",
                tint: .gray
            )
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let currentSession {
                VStack(alignment: .leading, spacing: 8) {
                    Text(isChinese ? "已登录账户" : "Signed In")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(currentSession.email.nonEmpty ?? currentSession.userID)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(
                        isChinese
                        ? "现在可以使用 AI 搭图、教案生成与参考文档解析。"
                        : "AI canvas assistance, lesson-plan generation, and reference parsing are now available."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    Button {
                        handleSignedInPrimaryAction()
                    } label: {
                        Text(allowsContinueWithoutAccount
                             ? (isChinese ? "进入工作区" : "Continue to Workspace")
                             : (isChinese ? "完成" : "Done"))
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        Task { await signOut() }
                    } label: {
                        Text(isChinese ? "退出登录" : "Sign Out")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(isChinese ? "邮箱登录" : "Email Sign-In")
                        .font(.headline)
                        .foregroundStyle(.white)

                    TextField(isChinese ? "邮箱" : "Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .padding(12)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    passwordField

                    HStack(spacing: 10) {
                        Button {
                            Task { await signIn() }
                        } label: {
                            authActionLabel(text: isChinese ? "登录" : "Sign In")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(authActionDisabled)

                        Button {
                            Task { await createAccount() }
                        } label: {
                            authActionLabel(text: isChinese ? "注册" : "Create Account")
                        }
                        .buttonStyle(.bordered)
                        .disabled(authActionDisabled)
                    }

                    Text(
                        isChinese
                        ? "邮箱和密码只用于当前登录或注册，不会保存在本地设备上。"
                        : "Your email and password are used only for the current sign-in or registration and are not stored on this device."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .cardStyle()
    }

    private var continueWithoutAccountButton: some View {
        Button {
            clearDraftCredentials()
            onContinueWithoutAccount?()
            dismiss()
        } label: {
            Text(isChinese ? "稍后进入" : "Continue without Account")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
    }

    private var accountServicesAvailable: Bool {
        backendConfiguration != nil
    }

    private var authActionDisabled: Bool {
        isAuthenticating
            || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || password.isEmpty
    }

    @ViewBuilder
    private func authActionLabel(text: String) -> some View {
        HStack(spacing: 8) {
            if isAuthenticating {
                ProgressView()
                    .controlSize(.small)
            }
            Text(text)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
    }

    private func messageCard(title: String, message: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
    }

    private var passwordField: some View {
        HStack(spacing: 10) {
            Group {
                if isPasswordVisible {
                    TextField(isChinese ? "密码" : "Password", text: $password)
                } else {
                    SecureField(isChinese ? "密码" : "Password", text: $password)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(.password)

            Button {
                isPasswordVisible.toggle()
            } label: {
                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isChinese
                    ? (isPasswordVisible ? "隐藏密码" : "显示密码")
                    : (isPasswordVisible ? "Hide password" : "Show password")
            )
        }
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func hydrateSession() {
        currentSession = EduBackendSessionStore.load()
    }

    @MainActor
    private func signIn() async {
        guard let authService = EduBackendAuthService() else {
            lastError = isChinese ? "当前构建尚未配置 EduNode 后端地址。" : "The EduNode backend is not configured in this build."
            return
        }

        isAuthenticating = true
        defer { isAuthenticating = false }
        lastError = nil
        infoMessage = nil

        do {
            let session = try await authService.signIn(
                email: email,
                password: password
            )
            currentSession = session
            clearDraftCredentials()
            handleSignedInPrimaryAction()
        } catch {
            lastError = error.localizedDescription
        }
    }

    @MainActor
    private func createAccount() async {
        guard let authService = EduBackendAuthService() else {
            lastError = isChinese ? "当前构建尚未配置 EduNode 后端地址。" : "The EduNode backend is not configured in this build."
            return
        }

        isAuthenticating = true
        defer { isAuthenticating = false }
        lastError = nil
        infoMessage = nil

        do {
            let result = try await authService.signUp(
                email: email,
                password: password
            )
            switch result {
            case .signedIn(let session):
                currentSession = session
                clearDraftCredentials()
                handleSignedInPrimaryAction()
            case .confirmationRequired(let email):
                password = ""
                infoMessage = isChinese
                    ? "账户已创建，请先检查 \(email) 的验证邮件，完成确认后再回来登录。"
                    : "Your account was created. Check the verification email sent to \(email), then come back and sign in."
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    @MainActor
    private func signOut() async {
        if let authService = EduBackendAuthService() {
            await authService.signOutCurrentSession()
        } else {
            EduBackendSessionStore.clear()
        }
        hydrateSession()
        clearDraftCredentials()
        lastError = nil
        infoMessage = isChinese ? "已退出账户登录。" : "Signed out from the account."
    }

    private func clearDraftCredentials() {
        email = ""
        password = ""
        isPasswordVisible = false
    }

    private func handleSignedInPrimaryAction() {
        onSaved?()
        dismiss()
    }
}

private extension View {
    func cardStyle() -> some View {
        padding(16)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
