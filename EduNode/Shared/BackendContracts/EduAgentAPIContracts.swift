import Foundation

public struct EduLLMMessage: Codable, Hashable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct EduAgentProviderSettingsPayload: Codable, Hashable, Sendable {
    public let providerName: String
    public let baseURLString: String
    public let model: String
    public let apiKey: String
    public let temperature: Double
    public let maxTokens: Int
    public let timeoutSeconds: Double
    public let additionalSystemPrompt: String

    public init(
        providerName: String,
        baseURLString: String,
        model: String,
        apiKey: String,
        temperature: Double,
        maxTokens: Int,
        timeoutSeconds: Double,
        additionalSystemPrompt: String
    ) {
        self.providerName = providerName
        self.baseURLString = baseURLString
        self.model = model
        self.apiKey = apiKey
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.timeoutSeconds = timeoutSeconds
        self.additionalSystemPrompt = additionalSystemPrompt
    }
}

public struct EduAgentConversationTurn: Codable, Hashable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct EduAgentSuggestedPromptsResponse: Codable, Hashable, Sendable {
    public let suggestions: [String]

    public init(suggestions: [String]) {
        self.suggestions = suggestions
    }
}

public struct EduAgentRuntimeStatusResponse: Codable, Hashable, Sendable {
    public let llmConfigured: Bool
    public let providerReachable: Bool
    public let providerName: String
    public let activeModel: String
    public let baseURLHost: String
    public let availableModels: [String]
    public let message: String

    public init(
        llmConfigured: Bool,
        providerReachable: Bool,
        providerName: String,
        activeModel: String,
        baseURLHost: String,
        availableModels: [String],
        message: String
    ) {
        self.llmConfigured = llmConfigured
        self.providerReachable = providerReachable
        self.providerName = providerName
        self.activeModel = activeModel
        self.baseURLHost = baseURLHost
        self.availableModels = availableModels
        self.message = message
    }

    enum CodingKeys: String, CodingKey {
        case llmConfigured = "llm_configured"
        case providerReachable = "provider_reachable"
        case providerName = "provider_name"
        case activeModel = "active_model"
        case baseURLHost = "base_url_host"
        case availableModels = "available_models"
        case message
    }
}

public struct EduBackendAuthSessionStatusResponse: Codable, Hashable, Sendable {
    public let authenticated: Bool
    public let userID: String
    public let email: String
    public let expiresAtUnixSeconds: Int64

    public init(
        authenticated: Bool,
        userID: String,
        email: String,
        expiresAtUnixSeconds: Int64
    ) {
        self.authenticated = authenticated
        self.userID = userID
        self.email = email
        self.expiresAtUnixSeconds = expiresAtUnixSeconds
    }

    enum CodingKeys: String, CodingKey {
        case authenticated
        case userID = "user_id"
        case email
        case expiresAtUnixSeconds = "expires_at_unix_seconds"
    }
}

public struct EduBackendAuthEmailPasswordRequest: Codable, Hashable, Sendable {
    public let email: String
    public let password: String

    public init(
        email: String,
        password: String
    ) {
        self.email = email
        self.password = password
    }
}

public struct EduBackendAuthRefreshRequest: Codable, Hashable, Sendable {
    public let refreshToken: String

    public init(refreshToken: String) {
        self.refreshToken = refreshToken
    }

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

public struct EduBackendAuthTokenSessionResponse: Codable, Hashable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let userID: String
    public let email: String
    public let expiresAtUnixSeconds: Int64

    public init(
        accessToken: String,
        refreshToken: String,
        userID: String,
        email: String,
        expiresAtUnixSeconds: Int64
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.userID = userID
        self.email = email
        self.expiresAtUnixSeconds = expiresAtUnixSeconds
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case userID = "user_id"
        case email
        case expiresAtUnixSeconds = "expires_at_unix_seconds"
    }
}

public struct EduBackendAuthSignUpResponse: Codable, Hashable, Sendable {
    public let status: String
    public let email: String
    public let session: EduBackendAuthTokenSessionResponse?

    public init(
        status: String,
        email: String,
        session: EduBackendAuthTokenSessionResponse?
    ) {
        self.status = status
        self.email = email
        self.session = session
    }
}

public struct EduBackendLLMCompletionRequest: Codable, Hashable, Sendable {
    public let messages: [EduLLMMessage]

    public init(messages: [EduLLMMessage]) {
        self.messages = messages
    }
}

public struct EduBackendLLMCompletionResponse: Codable, Hashable, Sendable {
    public let content: String

    public init(content: String) {
        self.content = content
    }
}

public struct EduBackendReferenceParsePDFRequest: Codable, Hashable, Sendable {
    public let fileName: String
    public let fileDataBase64: String

    public init(
        fileName: String,
        fileDataBase64: String
    ) {
        self.fileName = fileName
        self.fileDataBase64 = fileDataBase64
    }

    enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case fileDataBase64 = "file_data_base64"
    }
}

public struct EduBackendReferenceParsePDFResponse: Codable, Hashable, Sendable {
    public let taskID: String
    public let markdown: String
    public let rawResultJSON: String

    public init(
        taskID: String,
        markdown: String,
        rawResultJSON: String
    ) {
        self.taskID = taskID
        self.markdown = markdown
        self.rawResultJSON = rawResultJSON
    }

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case markdown
        case rawResultJSON = "raw_result_json"
    }
}

public struct EduAgentThinkingPlanResponse: Codable, Hashable, Sendable {
    public let decisionMode: String
    public let thinkingTraceMarkdown: String

    public init(
        decisionMode: String,
        thinkingTraceMarkdown: String
    ) {
        self.decisionMode = decisionMode
        self.thinkingTraceMarkdown = thinkingTraceMarkdown
    }

    enum CodingKeys: String, CodingKey {
        case decisionMode = "decision_mode"
        case thinkingTraceMarkdown = "thinking_trace_markdown"
    }
}

public struct EduAgentGraphOperationEnvelope: Codable, Hashable, Sendable {
    public let assistantReply: String
    public let thinkingTraceMarkdown: String?
    public let operations: [EduAgentGraphOperation]

    public init(
        assistantReply: String,
        thinkingTraceMarkdown: String? = nil,
        operations: [EduAgentGraphOperation]
    ) {
        self.assistantReply = assistantReply
        self.thinkingTraceMarkdown = thinkingTraceMarkdown
        self.operations = operations
    }

    enum CodingKeys: String, CodingKey {
        case assistantReply = "assistant_reply"
        case thinkingTraceMarkdown = "thinking_trace_markdown"
        case operations
    }
}

public struct EduAgentGraphOperation: Codable, Hashable, Sendable {
    public let op: String
    public let tempID: String?
    public let nodeRef: String?
    public let sourceNodeRef: String?
    public let targetNodeRef: String?
    public let nodeType: String?
    public let title: String?
    public let textValue: String?
    public let selectedOption: String?
    public let selectedMethodID: String?
    public let textFieldValues: [String: String]?
    public let optionFieldValues: [String: String]?
    public let anchorNodeRef: String?
    public let placement: String?
    public let sourcePortName: String?
    public let targetPortName: String?
    public let positionX: Double?
    public let positionY: Double?

    public init(
        op: String,
        tempID: String? = nil,
        nodeRef: String? = nil,
        sourceNodeRef: String? = nil,
        targetNodeRef: String? = nil,
        nodeType: String? = nil,
        title: String? = nil,
        textValue: String? = nil,
        selectedOption: String? = nil,
        selectedMethodID: String? = nil,
        textFieldValues: [String: String]? = nil,
        optionFieldValues: [String: String]? = nil,
        anchorNodeRef: String? = nil,
        placement: String? = nil,
        sourcePortName: String? = nil,
        targetPortName: String? = nil,
        positionX: Double? = nil,
        positionY: Double? = nil
    ) {
        self.op = op
        self.tempID = tempID
        self.nodeRef = nodeRef
        self.sourceNodeRef = sourceNodeRef
        self.targetNodeRef = targetNodeRef
        self.nodeType = nodeType
        self.title = title
        self.textValue = textValue
        self.selectedOption = selectedOption
        self.selectedMethodID = selectedMethodID
        self.textFieldValues = textFieldValues
        self.optionFieldValues = optionFieldValues
        self.anchorNodeRef = anchorNodeRef
        self.placement = placement
        self.sourcePortName = sourcePortName
        self.targetPortName = targetPortName
        self.positionX = positionX
        self.positionY = positionY
    }

    enum CodingKeys: String, CodingKey {
        case op
        case tempID = "temp_id"
        case nodeRef = "node_ref"
        case sourceNodeRef = "source_node_ref"
        case targetNodeRef = "target_node_ref"
        case nodeType = "node_type"
        case title
        case textValue = "text_value"
        case selectedOption = "selected_option"
        case selectedMethodID = "selected_method_id"
        case textFieldValues = "text_field_values"
        case optionFieldValues = "option_field_values"
        case anchorNodeRef = "anchor_node_ref"
        case placement
        case sourcePortName = "source_port_name"
        case targetPortName = "target_port_name"
        case positionX = "position_x"
        case positionY = "position_y"
    }
}

public struct EduAgentCourseSnapshot: Codable, Hashable, Sendable {
    public let name: String
    public let subject: String
    public let gradeMode: String
    public let gradeMin: Int
    public let gradeMax: Int
    public let lessonDurationMinutes: Int
    public let studentCount: Int
    public let periodRange: String
    public let goalsText: String
    public let modelID: String
    public let teacherTeam: String
    public let studentPriorKnowledgeLevel: String
    public let studentMotivationLevel: String
    public let studentSupportNotes: String
    public let resourceConstraints: String

    public init(
        name: String,
        subject: String,
        gradeMode: String,
        gradeMin: Int,
        gradeMax: Int,
        lessonDurationMinutes: Int,
        studentCount: Int,
        periodRange: String,
        goalsText: String,
        modelID: String,
        teacherTeam: String,
        studentPriorKnowledgeLevel: String,
        studentMotivationLevel: String,
        studentSupportNotes: String,
        resourceConstraints: String
    ) {
        self.name = name
        self.subject = subject
        self.gradeMode = gradeMode
        self.gradeMin = gradeMin
        self.gradeMax = gradeMax
        self.lessonDurationMinutes = lessonDurationMinutes
        self.studentCount = studentCount
        self.periodRange = periodRange
        self.goalsText = goalsText
        self.modelID = modelID
        self.teacherTeam = teacherTeam
        self.studentPriorKnowledgeLevel = studentPriorKnowledgeLevel
        self.studentMotivationLevel = studentMotivationLevel
        self.studentSupportNotes = studentSupportNotes
        self.resourceConstraints = resourceConstraints
    }
}

public struct EduAgentNodeFieldSnapshot: Codable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let value: String

    public init(id: String, label: String, value: String) {
        self.id = id
        self.label = label
        self.value = value
    }
}

public struct EduAgentGraphNodeSnapshot: Codable, Hashable, Sendable {
    public let id: String
    public let nodeType: String
    public let nodeFamily: String
    public let title: String
    public let textValue: String
    public let selectedOption: String
    public let selectedMethodID: String?
    public let positionX: Double
    public let positionY: Double
    public let incomingNodeIDs: [String]
    public let outgoingNodeIDs: [String]
    public let incomingTitles: [String]
    public let outgoingTitles: [String]
    public let textFields: [EduAgentNodeFieldSnapshot]
    public let optionFields: [EduAgentNodeFieldSnapshot]

    public init(
        id: String,
        nodeType: String,
        nodeFamily: String,
        title: String,
        textValue: String,
        selectedOption: String,
        selectedMethodID: String?,
        positionX: Double,
        positionY: Double,
        incomingNodeIDs: [String],
        outgoingNodeIDs: [String],
        incomingTitles: [String],
        outgoingTitles: [String],
        textFields: [EduAgentNodeFieldSnapshot],
        optionFields: [EduAgentNodeFieldSnapshot]
    ) {
        self.id = id
        self.nodeType = nodeType
        self.nodeFamily = nodeFamily
        self.title = title
        self.textValue = textValue
        self.selectedOption = selectedOption
        self.selectedMethodID = selectedMethodID
        self.positionX = positionX
        self.positionY = positionY
        self.incomingNodeIDs = incomingNodeIDs
        self.outgoingNodeIDs = outgoingNodeIDs
        self.incomingTitles = incomingTitles
        self.outgoingTitles = outgoingTitles
        self.textFields = textFields
        self.optionFields = optionFields
    }
}

public struct EduAgentGraphConnectionSnapshot: Codable, Hashable, Sendable {
    public let sourceNodeID: String
    public let sourcePortName: String
    public let targetNodeID: String
    public let targetPortName: String
    public let dataType: String

    public init(
        sourceNodeID: String,
        sourcePortName: String,
        targetNodeID: String,
        targetPortName: String,
        dataType: String
    ) {
        self.sourceNodeID = sourceNodeID
        self.sourcePortName = sourcePortName
        self.targetNodeID = targetNodeID
        self.targetPortName = targetPortName
        self.dataType = dataType
    }
}

public struct EduAgentSlideSnapshot: Codable, Hashable, Sendable {
    public let slideID: String
    public let title: String
    public let subtitle: String
    public let knowledgeItems: [String]
    public let toolkitItems: [String]
    public let keyPoints: [String]
    public let speakerNotes: [String]

    public init(
        slideID: String,
        title: String,
        subtitle: String,
        knowledgeItems: [String],
        toolkitItems: [String],
        keyPoints: [String],
        speakerNotes: [String]
    ) {
        self.slideID = slideID
        self.title = title
        self.subtitle = subtitle
        self.knowledgeItems = knowledgeItems
        self.toolkitItems = toolkitItems
        self.keyPoints = keyPoints
        self.speakerNotes = speakerNotes
    }
}

public struct EduAgentSupportedCanvasMethodSnapshot: Codable, Hashable, Sendable {
    public let methodID: String
    public let title: String
    public let textFields: [EduAgentNodeFieldSnapshot]
    public let optionFields: [EduAgentNodeFieldSnapshot]

    public init(
        methodID: String,
        title: String,
        textFields: [EduAgentNodeFieldSnapshot],
        optionFields: [EduAgentNodeFieldSnapshot]
    ) {
        self.methodID = methodID
        self.title = title
        self.textFields = textFields
        self.optionFields = optionFields
    }
}

public struct EduAgentSupportedCanvasNodeSnapshot: Codable, Hashable, Sendable {
    public let nodeType: String
    public let title: String
    public let methods: [EduAgentSupportedCanvasMethodSnapshot]
    public let directTextEditable: Bool
    public let directSelectableOptions: [String]

    public init(
        nodeType: String,
        title: String,
        methods: [EduAgentSupportedCanvasMethodSnapshot],
        directTextEditable: Bool,
        directSelectableOptions: [String]
    ) {
        self.nodeType = nodeType
        self.title = title
        self.methods = methods
        self.directTextEditable = directTextEditable
        self.directSelectableOptions = directSelectableOptions
    }
}

public struct EduAgentWorkspaceSnapshot: Codable, Hashable, Sendable {
    public let course: EduAgentCourseSnapshot
    public let nodes: [EduAgentGraphNodeSnapshot]
    public let connections: [EduAgentGraphConnectionSnapshot]
    public let slides: [EduAgentSlideSnapshot]
    public let lessonPlanMarkdown: String?

    public init(
        course: EduAgentCourseSnapshot,
        nodes: [EduAgentGraphNodeSnapshot],
        connections: [EduAgentGraphConnectionSnapshot],
        slides: [EduAgentSlideSnapshot],
        lessonPlanMarkdown: String?
    ) {
        self.course = course
        self.nodes = nodes
        self.connections = connections
        self.slides = slides
        self.lessonPlanMarkdown = lessonPlanMarkdown
    }
}

public struct EduAgentCanvasSchemaSnapshot: Codable, Hashable, Sendable {
    public let nodes: [EduAgentSupportedCanvasNodeSnapshot]

    public init(nodes: [EduAgentSupportedCanvasNodeSnapshot]) {
        self.nodes = nodes
    }
}

public struct EduCanvasAgentAutoRequest: Codable, Hashable, Sendable {
    public let workspace: EduAgentWorkspaceSnapshot
    public let schema: EduAgentCanvasSchemaSnapshot
    public let conversation: [EduAgentConversationTurn]
    public let userRequest: String
    public let supplementaryMaterial: String
    public let thinkingEnabled: Bool
    public let interfaceLanguageCode: String

    public init(
        workspace: EduAgentWorkspaceSnapshot,
        schema: EduAgentCanvasSchemaSnapshot,
        conversation: [EduAgentConversationTurn],
        userRequest: String,
        supplementaryMaterial: String,
        thinkingEnabled: Bool,
        interfaceLanguageCode: String
    ) {
        self.workspace = workspace
        self.schema = schema
        self.conversation = conversation
        self.userRequest = userRequest
        self.supplementaryMaterial = supplementaryMaterial
        self.thinkingEnabled = thinkingEnabled
        self.interfaceLanguageCode = interfaceLanguageCode
    }
}

public struct EduCanvasSuggestedPromptsRequest: Codable, Hashable, Sendable {
    public let workspace: EduAgentWorkspaceSnapshot
    public let supplementaryMaterial: String
    public let interfaceLanguageCode: String

    public init(
        workspace: EduAgentWorkspaceSnapshot,
        supplementaryMaterial: String,
        interfaceLanguageCode: String
    ) {
        self.workspace = workspace
        self.supplementaryMaterial = supplementaryMaterial
        self.interfaceLanguageCode = interfaceLanguageCode
    }
}
