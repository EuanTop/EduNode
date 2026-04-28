import Vapor
import EduNodeBackendCore

struct EduServerRuntimeConfiguration {
    let agentMode: EduCanvasAgentServiceMode
    let supabaseConfiguration: EduServerSupabaseConfiguration
    let llmSettings: EduAgentProviderSettingsResolved
    let minerUSettings: EduServerMinerUSettings?
}

private struct EduServerRuntimeConfigurationKey: StorageKey {
    typealias Value = EduServerRuntimeConfiguration
}

extension Application {
    var eduServerRuntimeConfiguration: EduServerRuntimeConfiguration {
        get {
            storage[EduServerRuntimeConfigurationKey.self] ?? EduServerRuntimeConfiguration(
                agentMode: .live,
                supabaseConfiguration: EduServerSupabaseConfiguration(
                    urlString: "",
                    publishableKey: ""
                ),
                llmSettings: EduServerEnvironmentLoader.defaultLLMSettings,
                minerUSettings: nil
            )
        }
        set {
            storage[EduServerRuntimeConfigurationKey.self] = newValue
        }
    }
}

func configure(_ app: Application) throws {
    let env = EduServerEnvironmentLoader.loadMergedEnvironment()

    if let host = env["EDUNODE_SERVER_HOST"], !host.isEmpty {
        app.http.server.configuration.hostname = host
    } else {
        app.http.server.configuration.hostname = "127.0.0.1"
    }

    if let portString = env["PORT"],
       let port = Int(portString) {
        app.http.server.configuration.port = port
    } else {
        app.http.server.configuration.port = 8080
    }

    let agentMode = EduCanvasAgentServiceMode(
        rawValue: env["EDUNODE_SERVER_AGENT_MODE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    ) ?? .live
    app.eduServerRuntimeConfiguration = EduServerRuntimeConfiguration(
        agentMode: agentMode,
        supabaseConfiguration: EduServerEnvironmentLoader.supabaseConfiguration(from: env),
        llmSettings: EduServerEnvironmentLoader.llmSettings(from: env),
        minerUSettings: EduServerEnvironmentLoader.minerUSettings(from: env)
    )

    try routes(app)
}
