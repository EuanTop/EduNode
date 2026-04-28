import Vapor
import EduNodeContracts

extension EduCanvasAgentAutoRequest: Content {}
extension EduCanvasSuggestedPromptsRequest: Content {}
extension EduAgentGraphOperationEnvelope: Content {}
extension EduAgentSuggestedPromptsResponse: Content {}
extension EduAgentRuntimeStatusResponse: Content {}
extension EduBackendAuthSessionStatusResponse: Content {}
extension EduBackendAuthEmailPasswordRequest: Content {}
extension EduBackendAuthRefreshRequest: Content {}
extension EduBackendAuthTokenSessionResponse: Content {}
extension EduBackendAuthSignUpResponse: Content {}
extension EduBackendLLMCompletionRequest: Content {}
extension EduBackendLLMCompletionResponse: Content {}
extension EduBackendReferenceParsePDFRequest: Content {}
extension EduBackendReferenceParsePDFResponse: Content {}
