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

    @State private var draft = EduAgentSettingsStore.load()
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testSucceeded = false
    @State private var availableModels: [String] = []
    @State private var isRefreshingModels = false
    @State private var modelRefreshMessage: String?
    @State private var autoTestTaskID = UUID()
    @State private var revealAPIKey = false
    @State private var isModelListExpanded = false

    let onSaved: (() -> Void)?

    init(onSaved: (() -> Void)? = nil) {
        self.onSaved = onSaved
    }

    private var isChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    configSection
                    tuningSection
                    promptSection
                    testSection
                }
                .padding(20)
            }
            .background(Color(white: 0.08).ignoresSafeArea())
            .navigationTitle(isChinese ? "模型设置" : "Model Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isChinese ? "关闭" : "Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isChinese ? "保存" : "Save") {
                        EduAgentSettingsStore.save(draft)
                        onSaved?()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task(id: autoTestTaskID) {
            await runAutoConnectionTestIfNeeded()
        }
        .onChange(of: draft.providerName) { _, _ in scheduleAutoConnectionTest() }
        .onChange(of: draft.baseURLString) { _, _ in scheduleAutoConnectionTest() }
        .onChange(of: draft.model) { _, _ in scheduleAutoConnectionTest() }
        .onChange(of: draft.apiKey) { _, _ in scheduleAutoConnectionTest() }
    }

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(isChinese ? "基础配置" : "Provider")
            settingsTextField(
                title: isChinese ? "Provider 名称" : "Provider Name",
                text: $draft.providerName,
                placeholder: "OpenAI-Compatible"
            )
            settingsTextField(
                title: isChinese ? "Base URL" : "Base URL",
                text: $draft.baseURLString,
                placeholder: "https://api.openai.com/v1"
            )
            apiKeyField
            modelField
        }
        .padding(16)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var modelField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isChinese ? "Model" : "Model")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                Circle()
                    .fill(draft.trimmedModel.isEmpty ? Color.orange : Color.green)
                    .frame(width: 6, height: 6)

                TextField("gpt-4.1", text: $draft.model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(maxWidth: .infinity)
                    .font(.system(size: 13, weight: .semibold))

                Button {
                    Task { await refreshModels() }
                } label: {
                    if isRefreshingModels {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isRefreshingModels || draft.trimmedBaseURLString.isEmpty || draft.trimmedAPIKey.isEmpty)

                Button {
                    isModelListExpanded.toggle()
                } label: {
                    Image(systemName: isModelListExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(availableModels.isEmpty && !isRefreshingModels)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 42)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )

            if isModelListExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    if availableModels.isEmpty {
                        Text(isChinese ? "请先刷新模型列表" : "Refresh the model list first")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(availableModels, id: \.self) { model in
                                    Button {
                                        draft.model = model
                                        isModelListExpanded = false
                                    } label: {
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(model == draft.trimmedModel ? Color.green : Color.clear)
                                                .frame(width: 6, height: 6)
                                            Text(model)
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Spacer(minLength: 0)
                                            if model == draft.trimmedModel {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundStyle(.green)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .frame(height: 30)
                                        .background(
                                            Color.green.opacity(model == draft.trimmedModel ? 0.14 : 0.02),
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 210)
                    }
                }
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
            }

            if let modelRefreshMessage {
                Text(modelRefreshMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var tuningSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(isChinese ? "请求参数" : "Request Tuning")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Temperature")
                    Spacer()
                    Text(String(format: "%.2f", draft.temperature))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $draft.temperature, in: 0...1.5, step: 0.05)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(isChinese ? "Max Tokens" : "Max Tokens")
                    Spacer()
                    Text("\(draft.maxTokens)")
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(draft.maxTokens) },
                        set: { draft.maxTokens = Int($0.rounded()) }
                    ),
                    in: 1024...8192,
                    step: 256
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(isChinese ? "超时（秒）" : "Timeout (s)")
                    Spacer()
                    Text("\(Int(draft.timeoutSeconds.rounded()))")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $draft.timeoutSeconds, in: 30...240, step: 5)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(isChinese ? "附加系统提示" : "Additional System Prompt")
            Text(isChinese
                 ? "这里适合放你对自定义模型的全局要求，比如语言风格、输出语气或额外约束。"
                 : "Use this for provider-specific global guidance such as preferred tone or output constraints.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $draft.additionalSystemPrompt)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 132)
                .padding(10)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
        .padding(16)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(isChinese ? "连通性检查" : "Connection Test")
            HStack(spacing: 8) {
                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(
                    isTesting
                        ? (isChinese ? "正在自动测试当前配置..." : "Automatically testing the current configuration...")
                        : (isChinese ? "配置变更后会自动测试连接。" : "Connection tests run automatically after configuration changes.")
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            if let testMessage {
                Label(testMessage, systemImage: testSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(testSucceeded ? .green : .orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func settingsTextField(
        title: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .frame(minHeight: 42)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
    }

    private var apiKeyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isChinese ? "API Key" : "API Key")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                if revealAPIKey {
                    TextField("", text: $draft.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField("", text: $draft.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Button {
                    revealAPIKey.toggle()
                } label: {
                    Image(systemName: revealAPIKey ? "eye.slash" : "eye")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 42)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            if draft.trimmedAPIKey.isEmpty {
                Text(isChinese ? "当前为空，表示尚未配置 API Key。" : "Currently empty, which means no API key is configured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.white)
    }

    @MainActor
    private func runConnectionTest() async {
        isTesting = true
        defer { isTesting = false }

        do {
            let client = EduOpenAICompatibleClient(settings: draft)
            let reply = try await client.complete(messages: [
                EduLLMMessage(role: "system", content: "Reply with a short confirmation."),
                EduLLMMessage(role: "user", content: "Return OK.")
            ])
            testSucceeded = true
            let normalizedReply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = isChinese
                ? "连接成功。当前配置模型：\(draft.trimmedModel)" + (normalizedReply.isEmpty ? "" : "。回复：\(normalizedReply)")
                : "Connection succeeded. Configured model: \(draft.trimmedModel)" + (normalizedReply.isEmpty ? "" : ". Reply: \(normalizedReply)")
            testMessage = message
            EduAgentConnectionStatusStore.saveResult(
                isReachable: true,
                message: message,
                for: draft
            )
        } catch {
            testSucceeded = false
            let message = error.localizedDescription
            testMessage = message
            EduAgentConnectionStatusStore.saveResult(
                isReachable: false,
                message: message,
                for: draft
            )
        }
    }

    @MainActor
    private func refreshModels() async {
        isRefreshingModels = true
        defer { isRefreshingModels = false }

        do {
            let client = EduOpenAICompatibleClient(settings: draft)
            let models = try await client.listModels()
            availableModels = models
            if draft.trimmedModel.isEmpty, let first = models.first {
                draft.model = first
            }
            modelRefreshMessage = isChinese
                ? "已加载 \(models.count) 个模型。"
                : "Loaded \(models.count) models."
        } catch {
            availableModels = []
            modelRefreshMessage = error.localizedDescription
        }
    }

    private func scheduleAutoConnectionTest() {
        autoTestTaskID = UUID()
    }

    @MainActor
    private func runAutoConnectionTestIfNeeded() async {
        guard draft.isConfigured else {
            isTesting = false
            testSucceeded = false
            testMessage = nil
            return
        }
        try? await Task.sleep(nanoseconds: 800_000_000)
        await runConnectionTest()
    }
}
