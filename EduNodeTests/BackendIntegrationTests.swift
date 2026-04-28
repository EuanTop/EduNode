import Foundation
import CoreGraphics
import Testing
import GNodeKit
@testable import EduNode

@MainActor
struct BackendIntegrationTests {
    @Test func workspaceAgentRemoteRoundTripSucceedsAgainstMockBackend() async throws {
        let env = integrationEnvironment()
        let backendURLString = trimmed(env["EDUNODE_TEST_BACKEND_URL"]) ?? "http://127.0.0.1:18081"
        let backendURL = try #require(URL(string: backendURLString))

        guard try await prepareIntegrationSession(
            env: env,
            allowDummyAccessToken: true
        ) else { return }
        defer { EduBackendSessionStore.clear() }

        let backendConfig = EduBackendServiceConfig(baseURL: backendURL)
        let service = EduWorkspaceAgentService(backendConfig: backendConfig)
        let resolvedService = try #require(service)
        let file = try makeIntegrationWorkspaceFile()

        let suggestions = try await resolvedService.suggestedPrompts(
            file: file,
            supplementaryMaterial: "教师希望保持探究式节奏，并让下一步操作更可执行。"
        )

        #expect(suggestions.count == 3)
        #expect(suggestions.allSatisfy { suggestion in
            !suggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })

        let envelope = try await resolvedService.send(
            file: file,
            conversation: [],
            userRequest: "请直接在当前节点画布中补一个评价节点，并与现有活动链条连接起来，保持改动最小。",
            supplementaryMaterial: "课程仍缺少与现有观察活动衔接的评价设计，请优先补足这一点。",
            thinkingEnabled: true
        )

        let allowedOps = Set(["add_node", "update_node", "connect", "disconnect", "move_node", "delete_node"])
        #expect(!envelope.assistantReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(!envelope.operations.isEmpty)
        #expect(envelope.operations.allSatisfy { allowedOps.contains($0.op) })
        if let thinking = envelope.thinkingTraceMarkdown {
            #expect(!thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @Test func workspaceAgentRemoteRoundTripSucceedsAgainstRealProviderWhenExplicitlyEnabled() async throws {
        let env = integrationEnvironment()
        guard trimmed(env["EDUNODE_RUN_REAL_PROVIDER_TESTS"]) == "1" else {
            return
        }

        let backendURLString = trimmed(env["EDUNODE_TEST_BACKEND_URL"]) ?? "http://127.0.0.1:18081"
        let backendURL = try #require(URL(string: backendURLString))

        guard try await prepareIntegrationSession(
            env: env,
            allowDummyAccessToken: false
        ) else { return }
        defer { EduBackendSessionStore.clear() }

        let backendConfig = EduBackendServiceConfig(baseURL: backendURL)
        let service = EduWorkspaceAgentService(backendConfig: backendConfig)
        let resolvedService = try #require(service)
        let file = try makeIntegrationWorkspaceFile()

        let suggestions = try await resolvedService.suggestedPrompts(
            file: file,
            supplementaryMaterial: "Teacher wants one more assessment checkpoint."
        )

        #expect(!suggestions.isEmpty)
    }
}

private func integrationEnvironment() -> [String: String] {
    let runtime = ProcessInfo.processInfo.environment
    let dotEnvValues = loadIntegrationDotEnvValues()
    return runtime.merging(dotEnvValues) { current, fallback in
        current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : current
    }
}

private func loadIntegrationDotEnvValues() -> [String: String] {
    let testFileURL = URL(fileURLWithPath: #filePath)
    let repoRoot = testFileURL.deletingLastPathComponent().deletingLastPathComponent()
    let candidateURLs = [
        repoRoot.appendingPathComponent("EduNode/.env"),
        repoRoot.appendingPathComponent(".env")
    ]

    for url in candidateURLs {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            continue
        }
        return parseIntegrationDotEnv(text)
    }
    return [:]
}

private func parseIntegrationDotEnv(_ text: String) -> [String: String] {
    text
        .split(whereSeparator: \.isNewline)
        .reduce(into: [String: String]()) { partial, rawLine in
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return }

            let normalizedLine: String
            if trimmed.hasPrefix("export ") {
                normalizedLine = String(trimmed.dropFirst("export ".count))
            } else {
                normalizedLine = trimmed
            }

            let segments = normalizedLine.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard segments.count == 2 else { return }

            let key = segments[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }

            var value = segments[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value.removeFirst()
                value.removeLast()
            }
            partial[key] = value
        }
}

private func trimmed(_ value: String?) -> String? {
    guard let value else { return nil }
    let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return result.isEmpty ? nil : result
}

@MainActor
private func prepareIntegrationSession(
    env: [String: String],
    allowDummyAccessToken: Bool
) async throws -> Bool {
    EduBackendSessionStore.clear()

    if let accessToken = trimmed(env["EDUNODE_TEST_SUPABASE_ACCESS_TOKEN"]) {
        let refreshToken = trimmed(env["EDUNODE_TEST_SUPABASE_REFRESH_TOKEN"]) ?? ""
        let userID = trimmed(env["EDUNODE_TEST_SUPABASE_USER_ID"]) ?? "integration-user"
        let email = trimmed(env["EDUNODE_TEST_SUPABASE_EMAIL"]) ?? "integration@example.com"
        let expiry = Int64(trimmed(env["EDUNODE_TEST_SUPABASE_EXPIRES_AT"]) ?? "")
            ?? Int64(Date().timeIntervalSince1970) + 3600

        EduBackendSessionStore.save(
            EduBackendSession(
                accessToken: accessToken,
                refreshToken: refreshToken,
                userID: userID,
                email: email,
                expiresAtUnixSeconds: expiry
            )
        )
        return true
    }

    if let email = trimmed(env["EDUNODE_TEST_SUPABASE_EMAIL"]),
       let password = trimmed(env["EDUNODE_TEST_SUPABASE_PASSWORD"]),
       let authService = EduSupabaseAuthService() {
        _ = try await authService.signIn(email: email, password: password)
        return true
    }

    if allowDummyAccessToken {
        EduBackendSessionStore.save(
            EduBackendSession(
                accessToken: "integration-dummy-access-token",
                refreshToken: "",
                userID: "integration-user",
                email: "integration@example.com",
                expiresAtUnixSeconds: Int64(Date().timeIntervalSince1970) + 3600
            )
        )
        return true
    }
    return false
}

@MainActor
private func makeIntegrationWorkspaceFile() throws -> GNodeWorkspaceFile {
    GNodeWorkspaceFile(
        name: "Remote Agent Integration",
        data: try makeIntegrationGraphData(),
        gradeLevel: "Grade 5",
        gradeMode: "grade",
        gradeMin: 5,
        gradeMax: 5,
        subject: "Science",
        lessonDurationMinutes: 45,
        allowOvertime: false,
        periodRange: "1",
        studentCount: 28,
        studentProfile: "Students are interested in birds but need clearer evidence-based observation tasks.",
        studentPriorKnowledgeLevel: "medium",
        studentMotivationLevel: "high",
        studentSupportNotes: "Some students need explicit comparison prompts.",
        goalsText: """
        Students can identify key bird features through observation.
        Students can connect observed features to habitat and behavior.
        """,
        modelID: "inquiry-driven",
        teacherTeam: "Lead teacher only",
        leadTeacherCount: 1,
        assistantTeacherCount: 0,
        teacherRolePlan: "Lead teacher guides observation and synthesis.",
        learningScenario: "Bird observation workshop",
        curriculumStandard: "Observation and evidence-based explanation",
        resourceConstraints: "Printed bird cards, projector",
        requireStructuredFlow: true
    )
}

@MainActor
private func makeIntegrationGraphData() throws -> Data {
    let knowledge = EduKnowledgeNode(
        name: "Bird Features",
        content: "Students identify beak, feet, habitat, and movement features from bird cards.",
        level: EduKnowledgeNode.defaultLevel
    )
    let toolkit = EduToolkitNode(
        name: "Observation Routine",
        category: .perceptionInquiry,
        selectedMethodID: "field_observation",
        textFieldValues: [
            "observation_target": "Bird cards and local bird photos",
            "observation_focus": "Beak, feet, habitat, and feeding behavior"
        ]
    )

    let serializedKnowledge = SerializableNode(from: knowledge, nodeType: EduNodeType.knowledge)
    let serializedToolkit = SerializableNode(from: toolkit, nodeType: EduNodeType.toolkitPerceptionInquiry)

    let connection = NodeConnection(
        sourceNode: serializedKnowledge.id,
        sourcePort: serializedKnowledge.outputPorts[0].id,
        targetNode: serializedToolkit.id,
        targetPort: serializedToolkit.inputPorts[0].id,
        dataType: serializedKnowledge.outputPorts[0].dataType
    )

    let document = GNodeDocument(
        nodes: [serializedKnowledge, serializedToolkit],
        connections: [connection],
        canvasState: [
            CanvasNodeState(nodeID: serializedKnowledge.id, position: CGPoint(x: 80, y: 120)),
            CanvasNodeState(nodeID: serializedToolkit.id, position: CGPoint(x: 360, y: 120))
        ]
    )

    return try encodeDocument(document)
}
