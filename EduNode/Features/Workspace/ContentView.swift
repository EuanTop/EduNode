//
//  ContentView.swift
//  EduNode
//
//  Created by Euan on 2/15/26.
//

import SwiftUI
import SwiftData
import GNodeKit
import UniformTypeIdentifiers
#if canImport(UIKit) && canImport(WebKit)
import UIKit
import WebKit
#endif
#if canImport(ImageIO)
import ImageIO
#endif

@MainActor
struct ContentView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.scenePhase) var scenePhase
    @Query(sort: \GNodeWorkspaceFile.createdAt, order: .forward) var workspaceFiles: [GNodeWorkspaceFile]
    @AppStorage("edunode.seeded_default_course.v1") var didSeedDefaultCourse = false
    @AppStorage("edunode.lastPersistLog") var lastPersistLog = ""
    @AppStorage("edunode.onboarding.completed.v1") var didCompleteOnboarding = false
    @AppStorage("edunode.tutorial.basics.completed.v1") var didCompleteBasics = false
    @AppStorage("edunode.tutorial.practice.completed.v1") var didCompletePractice = false
    @AppStorage("edunode.tutorial.explore.completed.v1") var didCompleteExplore = false

    @State var selectedFileID: UUID?
    @State var splitVisibility: NavigationSplitViewVisibility = .all
    @State var showingCreateCourseSheet = false
    @State var creationDraft = CourseCreationDraft()
    @State var showingStudentRosterEdit = false
    @State var studentRosterEditFileID: UUID?
    @State var showingEditCourseSheet = false
    @State var editingCourseFileID: UUID?
    @State var editingCourseOriginalModelID: String = ""
    @State var showingModelChangeWarning = false
    @State var showingDocs = false
    @State var docsPreferredNodeType: String?
    @State var showingOnboardingGuide = false
    @State var showingSidebarImporter = false
    @State var showingAccountSheet = false
    @State var showingStartupAccountGate = false
    @State var didResolveStartupAccountGate = false
    @State var backendSessionSnapshot: EduBackendSession?
    @State var workspaceToolbarExportDocument: EduWorkspaceToolbarExportDocument?
    @State var workspaceToolbarExportContentType: UTType = .json
    @State var workspaceToolbarExportFilename = "graph.gnode"
    @State var showingWorkspaceToolbarExporter = false
    @State var lessonPlanSetupPayload: EduLessonPlanSetupPayload?
    @State var lessonPlanPreviewPayload: EduLessonPlanPreviewPayload?
    @State var presentationPreviewPayload: EduPresentationPreviewPayload?
    @State var workspaceAgentSidebarFileID: UUID?
    @State var workspaceAgentConversationByFile: [UUID: [EduAgentConversationMessage]] = [:]
    @State var workspaceAgentPendingResponseByFile: [UUID: EduAgentGraphOperationEnvelope] = [:]
    @State var workspaceAgentReviewIndexByFile: [UUID: Int] = [:]
    @State var agentGraphUndoStackByFile: [UUID: [EduAgentGraphUndoSnapshot]] = [:]
    @State var showingPresentationEmptyAlert = false
    @State var activePresentationModeFileID: UUID?
    @State var activePresentationStylingFileID: UUID?
    @State var presentationModeLoadingFileID: UUID?
    @State var presentationModeActivationToken: UUID?
    @State var pendingPresentationThumbnailIDsByFile: [UUID: Set<UUID>] = [:]
    @State var presentationBreaksByFile: [UUID: Set<Int>] = [:]
    @State var presentationExcludedNodeIDsByFile: [UUID: Set<UUID>] = [:]
    @State var selectedPresentationGroupIDByFile: [UUID: UUID] = [:]
    @State var presentationStylingByFile: [UUID: [UUID: PresentationSlideStylingState]] = [:]
    @State var presentationPageStyleByFile: [UUID: PresentationPageStyle] = [:]
    @State var presentationTextThemeByFile: [UUID: PresentationTextTheme] = [:]
    @State var hydratedPresentationStateFileIDs: Set<UUID> = []
    @State var presentationStylingTouchedFileIDs: Set<UUID> = []
    @State var cameraRequest: NodeEditorCameraRequest?
    @State var pendingFlowStepConfirmation: EduFlowStep?
    @State var pendingFlowStepFileID: UUID?
    @State var pendingFlowStepIsDone = false
    @State var isSidebarBasicInfoExpanded = false
    @State var editorStatsByFileID: [UUID: NodeEditorCanvasStats] = [:]
    @State var initialCameraFocusToken: UUID?
    @State var modelTemplatePreviewByID: [String: ModelTemplatePreview] = [:]
    @State var selectedModelTemplatePreviewID: String?
    @State var inlineEvaluationScoreValuesByFile: [UUID: [InlineEvaluationScoreKey: String]] = [:]
    @State var inlineEvaluationCompletionValuesByFile: [UUID: [InlineEvaluationScoreKey: Bool]] = [:]
    @State var selectionRequest: NodeEditorSelectionRequest?
    @State var isHandlingPresentationButtonTap = false
    @State var tutorialHintPulsePhase = false
    @State var activeTutorial: TutorialKind?
    @State var tutorialStepIndex: Int = 0
    @State var tutorialPreviousNodeCount: Int = 0
    @State var tutorialPreviousConnectionCount: Int = 0
    @State var tutorialAutoAdvanceToken = UUID()
    @State var tutorialDedicatedFileID: UUID?
    @State var tutorialPracticeFileID: UUID?
    @State var tutorialPracticeBaselineSemanticData: Data?
    @State var tutorialPracticeHasEnteredPresentation = false
    @State var tutorialPracticeInitialToolkitCount: Int = 0
    @State var tutorialPracticeInitialConnections: Set<TutorialConnectionSignature> = []
    @State var tutorialPracticeInitialNodeIDs: Set<UUID> = []
    @State var tutorialPracticeInitialKnowledgeContentByNodeID: [UUID: String] = [:]
    @State var tutorialPracticeTopKnowledgeNodeIDs: [UUID] = []
    @State var tutorialPracticeKnowledgeModificationBaseline: Int?
    @State var tutorialPracticeKnowledgeStepTargetNodeID: UUID?
    @State var tutorialPracticeKnowledgeStepEntryContent: String?
    @State var tutorialPracticeConfiguredToolkitNodeID: UUID?
    @State var tutorialPracticeConnectionStepBaseline: Set<TutorialConnectionSignature>?
    @State var tutorialPracticeGuidedFillToken = UUID()
    @State var tutorialPracticeGuidedFillPendingStepIndex: Int?
    @State var tutorialPracticeInitialZoomPercent: Int = 100
    @State var tutorialPracticeZoomStepBaseline: Int?
    @State var tutorialCanvasEvaluationCountBeforeDelete: Int?
    @State var tutorialCanvasConnectionCountBeforeDelete: Int?
    @State var tutorialDesignButtonFrameInGlobal: CGRect = .zero
    let presentationPersistenceDebugEnabled = true

    let modelRules = EduPlanning.loadModelRules()
    var eduNodeMenuSections: [NodeMenuSectionConfig] {
        GNodeNodeKit.gnodeNodeKit.canvasMenuSections()
    }

    // When sidebar is hidden, reserve space for the system's circular sidebar reveal button.
    var topToolbarLeadingReservedWidth: CGFloat {
        splitVisibility == .detailOnly ? 52 : 0
    }
    let presentationFilmstripHeight: CGFloat = 186
    let tutorialRootCoordinateSpaceName = "TutorialRootCoordinateSpace"

    private var sidebarChromeBackground: Color {
        Color(white: 0.12)
    }

    private var sidebarLayoutDebugEnabled: Bool {
        false
    }

    private var workspaceSidebarColumnWidth: CGFloat {
        #if targetEnvironment(macCatalyst)
        return 320
        #else
        return 320
        #endif
    }

    var workspaceSidebarToggleLeadingPadding: CGFloat {
        #if targetEnvironment(macCatalyst)
        return splitVisibility == .detailOnly ? 96 : 112
        #else
        14
        #endif
    }

    private var workspaceSidebarHeaderLeadingPadding: CGFloat {
        workspaceSidebarToggleLeadingPadding
    }

    private var workspaceTopToolbarPadding: CGFloat {
        #if targetEnvironment(macCatalyst)
        return 18
        #else
        return 16
        #endif
    }

    var workspaceTopToolbarButtonHeight: CGFloat {
        #if targetEnvironment(macCatalyst)
        return 36
        #else
        return 32
        #endif
    }

    private var workspaceTopRightToolbarButtonWidth: CGFloat {
        #if targetEnvironment(macCatalyst)
        return 106
        #else
        return 112
        #endif
    }

    private var workspaceTopRightToolbarSpacing: CGFloat {
        #if targetEnvironment(macCatalyst)
        return 8
        #else
        return 10
        #endif
    }

    private var workspaceTopRightToolbarTrailingPadding: CGFloat {
        20
    }

    private var workspaceTopRightToolbarReservedWidth: CGFloat {
        (workspaceTopRightToolbarButtonWidth * 3)
            + (workspaceTopRightToolbarSpacing * 2)
            + workspaceTopRightToolbarTrailingPadding
            + 18
    }

    var usesCustomWorkspaceTopToolbar: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    private var courseCreationSheetMinHeight: CGFloat? {
        #if targetEnvironment(macCatalyst)
        return 760
        #else
        return nil
        #endif
    }

    private func stableWorkspaceTopInset(_ rawTopInset: CGFloat) -> CGFloat {
        #if targetEnvironment(macCatalyst)
        // Catalyst recalculates the titlebar/safe-area after our custom window
        // chrome is applied. Keeping the workspace chrome independent from that
        // transient value prevents the sidebar from jumping during launch.
        return 0
        #else
        return rawTopInset
        #endif
    }

    private var showsSidebarUtilityHeader: Bool {
        return true
    }

    var supportsInlineAccountEntry: Bool {
        return false
    }

    struct ResolvedPresentationSelection {
        let group: EduPresentationSlideGroup
        let slide: EduPresentationComposedSlide
    }

    struct ModelTemplatePreview: Identifiable {
        let id: String
        let modelRuleID: String
        let displayName: String
        let documentID: UUID
        var data: Data
    }

    enum EvaluationIndicatorKind {
        case score
        case completion
    }

    struct EvaluationIndicatorDescriptor: Identifiable {
        let id: String
        let name: String
        let kind: EvaluationIndicatorKind
    }

    struct EvaluationNodeDescriptor: Identifiable {
        let id: UUID
        let title: String
        let indicators: [EvaluationIndicatorDescriptor]
    }

    struct KnowledgeLevelCountChip: Identifiable {
        let id: String
        let title: String
        let count: Int
    }

    struct InlineEvaluationScoreKey: Hashable {
        let nodeID: UUID
        let indicatorID: String
        let studentName: String
    }

    struct StudentRosterEntry: Identifiable, Hashable {
        let sequence: Int
        let name: String
        let group: String

        var id: String { "\(sequence)-\(name)" }
    }

    struct PresentationTrackingSummary {
        let currentPage: Int
        let totalPages: Int
        let levelChips: [KnowledgeLevelCountChip]
        let activeKnowledgeLevelIDs: Set<String>
        let activeEvaluationNodes: [EvaluationNodeDescriptor]
        let studentRoster: [StudentRosterEntry]
        let isChinese: Bool

        var studentNames: [String] {
            studentRoster.map(\.name)
        }
    }

    struct TutorialSemanticSnapshot: Codable {
        let nodes: [SerializableNode]
        let connections: [NodeConnection]
        let canvasState: [CanvasNodeState]
    }

    struct TutorialConnectionSignature: Hashable {
        let sourceNodeID: UUID
        let sourcePortID: UUID
        let targetNodeID: UUID
        let targetPortID: UUID
    }

    struct TutorialDesignButtonFramePreferenceKey: PreferenceKey {
        static var defaultValue: CGRect = .zero

        static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
            let next = nextValue()
            if next.width > 1 && next.height > 1 {
                value = next
            }
        }
    }

    // MARK: - Tutorial System Types

    /// Tutorial flow (all within the "5-Min Basics" button):
    ///   aboutDemo  →  canvasBasics  →  modelsIntro  →  [delete tutorial file, show welcome]
    /// Then "Practice" button:
    ///   practice
    /// Then "Explore" button:
    ///   explore  →  done
    enum TutorialKind: Equatable {
        case aboutDemo             // Animated intro on blank canvas — nodes appear & connect automatically
        case canvasBasics          // Hands-on canvas ops on the same tutorial file
        case modelsIntro           // User opens Docs and browses Education Models
        case practice              // User creates a real course and works on it
        case explore               // User views bird example
    }

    enum TutorialAdvanceMode {
        case tapAnywhere           // Tap coach mark to advance
        case nodeAdded             // Auto-advance when node count increases
        case nodeDeleted           // Auto-advance when node count decreases
        case connectionAdded       // Auto-advance when connection count increases
        case connectionDeleted     // Auto-advance when connection count decreases
        case animationAuto         // Auto-advance after a timed delay (for demo animations)
        case waitForDocs           // Wait for user to open the docs panel
        case waitForModelDocSelection // Wait for user to select an Education Model entry in Docs
        case waitForCreateCourseSheet
        case waitForCourseCreated
        case waitForCanvasZoomOut
        case waitForKnowledgeKeywordEdit
        case waitForAdditionalKnowledgeEdit
        case waitForSpecificToolkitConfigured
        case waitForKnowledgeToSpecificToolkitConnectionAdded
        case waitForPresentationEnter
        case waitForStylingPanelEnter
        case waitForPresentationExit
        case waitForLessonPlanPreview
        case waitForPresentationPreview
        case waitForBirdExampleSelection
    }

    struct TutorialStep {
        let enMessage: String
        let zhMessage: String
        let advanceMode: TutorialAdvanceMode
        /// For animationAuto steps: which demo stage to trigger
        var demoAction: TutorialDemoAction?

        func message(chinese: Bool) -> String {
            chinese ? zhMessage : enMessage
        }
    }

    /// Actions performed during the aboutDemo phase
    enum TutorialDemoAction {
        case showKnowledgeNode
        case showToolkitNode
        case showEvaluationNode
        case connectKnowledgeToToolkit
        case connectToolkitToEvaluation
    }

    /// Whether the current tutorial phase runs inside the docs fullScreenCover
    var isTutorialInDocsPhase: Bool {
        activeTutorial == .modelsIntro && showingDocs
    }

    // ── About EduNode demo steps (animated on blank canvas) ──
    var aboutDemoSteps: [TutorialStep] {
        [
            TutorialStep(
                enMessage: "Welcome to EduNode! It helps every teacher design quality lessons — NOT replace teachers with AI.\nLet me show you the three core building blocks.",
                zhMessage: "欢迎来到 EduNode！它帮助每位教师设计高质量课堂——不会用 AI 取代教师。\n让我展示三种核心构建模块。",
                advanceMode: .tapAnywhere
            ),
            TutorialStep(
                enMessage: "This is a Knowledge node — it defines WHAT to teach.",
                zhMessage: "这是知识节点——它定义「学什么」。",
                advanceMode: .tapAnywhere,
                demoAction: .showKnowledgeNode
            ),
            TutorialStep(
                enMessage: "This is a Toolkit node — it defines HOW to teach.",
                zhMessage: "这是工具节点——它定义「怎么学」。",
                advanceMode: .tapAnywhere,
                demoAction: .showToolkitNode
            ),
            TutorialStep(
                enMessage: "This is an Evaluation node — it verifies HOW WELL students learn.",
                zhMessage: "这是评价节点——它验证「学得怎么样」。",
                advanceMode: .tapAnywhere,
                demoAction: .showEvaluationNode
            ),
            TutorialStep(
                enMessage: "Now watch — we auto-connect from Knowledge right output \"\(S("edu.knowledge.output.content")) (String)\" to Toolkit left input \"\(S("edu.toolkit.input.knowledge")) (Any)\".",
                zhMessage: "现在看——系统会自动从知识节点右侧输出「内容（String）」连到工具节点左侧输入「知识输入（Any）」。",
                advanceMode: .tapAnywhere,
                demoAction: .connectKnowledgeToToolkit
            ),
            TutorialStep(
                enMessage: "Next, Evaluation needs at least one indicator input. We auto-add \"Quick Check | score\", then connect Toolkit first output \"\(S("edu.output.toolkit")) (String)\" to Evaluation input \"Quick Check (Any)\".",
                zhMessage: "接着，评价节点必须先有至少一个指标输入。系统会自动添加「快速检查 | score」，再将工具节点第一个输出「\(S("edu.output.toolkit"))（String）」连到评价节点输入「快速检查（Any）」。",
                advanceMode: .tapAnywhere,
                demoAction: .connectToolkitToEvaluation
            ),
            TutorialStep(
                enMessage: "Your workflow:\n1. Create a course (subject, grade, goals)\n2. Build the canvas (add & connect nodes)\n3. Fill details (content, activities)\n4. Preview & Export (lesson plan, slides)\n\nNow let's practice these operations yourself!",
                zhMessage: "你的工作流：\n1. 新建课程（学科、学段、目标）\n2. 搭建画布（添加节点并连线）\n3. 填写细节（内容、活动）\n4. 预览与导出（教案、演示文稿）\n\n下面让我们亲手操作一下！",
                advanceMode: .tapAnywhere
            ),
        ]
    }

    // ── Canvas basics hands-on steps ──
    var canvasBasicsSteps: [TutorialStep] {
        [
            TutorialStep(
                enMessage: "The demo nodes have been cleared. Now it's your turn!\nDouble-tap anywhere to open the node menu, then add a Knowledge node.",
                zhMessage: "演示节点已清除，现在轮到你了！\n双击画布空白区域打开节点面板，添加一个知识节点。",
                advanceMode: .nodeAdded
            ),
            TutorialStep(
                enMessage: "Great! Now double-tap again and add ONE Toolkit node (any of the 4 Toolkit categories is accepted).",
                zhMessage: "很好！再次双击画布，添加 1 个工具节点（四类工具节点任意一种都可以）。",
                advanceMode: .nodeAdded
            ),
            TutorialStep(
                enMessage: "Connect them precisely: drag from Knowledge right output \"\(S("edu.knowledge.output.content")) (String)\" to Toolkit left input \"\(S("edu.toolkit.input.knowledge")) (Any)\".",
                zhMessage: "请精确连线：从知识节点右侧输出「内容（String）」拖到工具节点左侧输入「知识输入（Any）」。",
                advanceMode: .connectionAdded
            ),
            TutorialStep(
                enMessage: "Add an Evaluation node. Then in its Indicators table, add one row (for example: \"Quick Check | score\") so the left input port appears.",
                zhMessage: "添加一个评价节点。然后在它的指标表格里新增一行（例如「快速检查 | score」），这样左侧输入端口才会出现。",
                advanceMode: .nodeAdded
            ),
            TutorialStep(
                enMessage: "Now connect Toolkit first output \"\(S("edu.output.toolkit")) (String)\" to Evaluation indicator input (Any).",
                zhMessage: "现在连接工具节点第一个输出「\(S("edu.output.toolkit"))（String）」到评价节点指标输入端口（Any）。",
                advanceMode: .connectionAdded
            ),
            TutorialStep(
                enMessage: "Delete one Evaluation node: long-press that node to open quick actions, then tap Delete.",
                zhMessage: "删除 1 个评价节点：长按该节点呼出操作，再点击删除。",
                advanceMode: .nodeDeleted
            ),
            TutorialStep(
                enMessage: "One more operation: long-press an existing connection line to delete it.\nAfter you do this, we'll jump to Documentation automatically.",
                zhMessage: "最后一个操作：长按一条已有连线即可删除。\n完成后会自动跳转到文档页面介绍教育模型。",
                advanceMode: .connectionDeleted
            ),
        ]
    }

    // ── Models intro steps (shown overlaid on docs) ──
    var modelsIntroSteps: [TutorialStep] {
        [
            TutorialStep(
                enMessage: "This is the Documentation page. Education Models provide structural blueprints for your teaching chains.\nBrowse through the models in the sidebar — try tapping \"Kolb Experiential Learning\".",
                zhMessage: "这是文档页面。教育模型为教学链路提供结构蓝图。\n浏览侧栏中的模型——试试点击「Kolb 体验学习循环」。",
                advanceMode: .waitForModelDocSelection
            ),
            TutorialStep(
                enMessage: "Each model has a different node structure. When you create a course, EduNode recommends the best model for your needs.\n\n5-Min Basics complete. Moving to Practice.",
                zhMessage: "每种模型有不同的节点结构。创建课程时，EduNode 会推荐最合适的模型。\n\n5 分钟入门完成。正在进入实战训练。",
                advanceMode: .tapAnywhere
            ),
        ]
    }

    // ── Practice steps (on generated course canvas) ──
    var practiceSteps: [TutorialStep] {
        [
            TutorialStep(
                enMessage: "Click + to create a new course. We pre-fill the form for this guided practice.",
                zhMessage: "点击右上角 + 新建课程。实战训练中表单会自动预填。",
                advanceMode: .waitForCreateCourseSheet
            ),
            TutorialStep(
                enMessage: "Keep the pre-filled form and click Next/Create to generate the course template.",
                zhMessage: "保持预填信息，直接点击「下一步 / 创建」生成课程模板。",
                advanceMode: .waitForCourseCreated
            ),
            TutorialStep(
                enMessage: "Step 1: pinch to zoom out the canvas (about 80% or lower) and inspect the full UbD template structure first.",
                zhMessage: "第 1 步：先双指缩小画布（约 80% 或更小），完整查看 UbD 模板结构。",
                advanceMode: .waitForCanvasZoomOut
            ),
            TutorialStep(
                enMessage: "UbD quick walkthrough: we'll spotlight the top understanding chain in sequence, then move to a concrete Newton's First Law lesson adaptation.",
                zhMessage: "UbD 快速导览：系统会依次高亮上方“理解主链”，然后把它改造成「牛顿第一定律」课堂。",
                advanceMode: .tapAnywhere
            ),
            TutorialStep(
                enMessage: "Step 2 (Why): define what students must truly understand.\nSelect the highlighted \"UbD Stage 1: Desired Results\" node, then tap the guide-panel button \"Apply Guided Text\".",
                zhMessage: "第 2 步（为什么）：先定义学生真正要理解什么。\n选中高亮的「UbD 阶段1：预期结果」节点，然后点击下方引导面板按钮「填入教程示例」。",
                advanceMode: .waitForKnowledgeKeywordEdit
            ),
            TutorialStep(
                enMessage: "Step 3 (Why): decide what evidence will prove understanding.\nSelect the highlighted \"UbD Stage 2: Acceptable Evidence\" node, then tap \"Apply Guided Text\" in this guide panel.",
                zhMessage: "第 3 步（为什么）：明确用什么证据证明“学会了”。\n选中高亮的「UbD 阶段2：可接受证据」节点，然后点击本引导面板中的「填入教程示例」。",
                advanceMode: .waitForAdditionalKnowledgeEdit
            ),
            TutorialStep(
                enMessage: "Step 4 (Why): arrange activities in teaching order.\nSelect the highlighted \"UbD Stage 3: Learning Plan\" node, then tap \"Apply Guided Text\" in this guide panel.",
                zhMessage: "第 4 步（为什么）：把活动按教学顺序组织出来。\n选中高亮的「UbD 阶段3：学习体验规划」节点，然后点击本引导面板中的「填入教程示例」。",
                advanceMode: .waitForAdditionalKnowledgeEdit
            ),
            TutorialStep(
                enMessage: "Step 5 (Why): add a concrete evidence-analysis activity.\nCreate ONE \"Inquiry\" toolkit. The tutorial will auto-switch it to Source Analysis, fill fields, and auto-link it from \"UbD Stage 3: Learning Plan\" as the activity-flow driver.",
                zhMessage: "第 5 步（为什么）：补上一段“证据分析”活动。\n新增 1 个「探究」工具节点，教程会自动切到「资料分析」、填好参数，并自动接到「UbD 阶段3」作为活动流程驱动。",
                advanceMode: .waitForSpecificToolkitConfigured
            ),
            TutorialStep(
                enMessage: "Step 6: keep existing UbD links as-is.\nNow add ONE more link from \"UbD Stage 2: Acceptable Evidence\" output \"\(S("edu.knowledge.output.content"))\" to the highlighted Inquiry Toolkit (Source Analysis) input \"\(S("edu.toolkit.input.knowledge"))\".",
                zhMessage: "第 6 步：保持原有 UbD 连线不变。\n现在再新增 1 条连线：从「UbD 阶段2：可接受证据」输出「\(S("edu.knowledge.output.content"))」，连接到当前高亮的探究工具节点（资料分析）输入「\(S("edu.toolkit.input.knowledge"))」。",
                advanceMode: .waitForKnowledgeToSpecificToolkitConnectionAdded
            ),
            TutorialStep(
                enMessage: "Why this matters: for this same toolkit, Stage 3 defines activity sequence, while Stage 2 adds evidence criteria.\nIn Lesson Plan / PPT preview, this stage will now show extra evidence-alignment guidance.",
                zhMessage: "这一步的意义：对同一个工具节点，Stage 3 负责活动流程，Stage 2 负责证据标准。\n在教案/PPT 预览里，这个环节会出现额外的“证据对齐”提示。",
                advanceMode: .tapAnywhere
            ),
            TutorialStep(
                enMessage: "Now click Present to enter presentation mode.",
                zhMessage: "现在点击「演示」进入演示模式。",
                advanceMode: .waitForPresentationEnter
            ),
            TutorialStep(
                enMessage: "Click the Design button to open quick styling.",
                zhMessage: "点击「设计」按钮，进入快速美化。",
                advanceMode: .waitForStylingPanelEnter
            ),
            TutorialStep(
                enMessage: "Return and click Present again to exit presentation mode.",
                zhMessage: "返回后再次点击「演示」，退出演示模式。",
                advanceMode: .waitForPresentationExit
            ),
            TutorialStep(
                enMessage: "Use the Export button in the top-right toolbar, then open Lesson Plan Preview.\nCheck this toolkit section now includes evidence-alignment notes.",
                zhMessage: "请点击右上角「导出」按钮，然后打开「教案预览」。\n请查看该工具节点环节现在多了“证据对齐”说明。",
                advanceMode: .waitForLessonPlanPreview
            ),
            TutorialStep(
                enMessage: "Use the Export button in the top-right toolbar, then open PPT Preview.\nYou should see extra evidence cue text for the same activity slide.",
                zhMessage: "请点击右上角「导出」按钮，然后打开「PPT 预览」。\n同一活动页会出现额外的证据提示文本。",
                advanceMode: .waitForPresentationPreview
            ),
            TutorialStep(
                enMessage: "Practice complete. Next: explore the Zhuhai bird sample.",
                zhMessage: "实战训练完成。下一步：探索珠海观鸟优秀案例。",
                advanceMode: .animationAuto
            ),
        ]
    }

    // ── Explore step ──
    var exploreSteps: [TutorialStep] {
        [
            TutorialStep(
                enMessage: "Select \"Zhuhai Bird & Nest Workshop\" from the left file list.",
                zhMessage: "请在左侧课程列表中选择「珠海观鸟美育工作坊」。",
                advanceMode: .waitForBirdExampleSelection
            ),
            TutorialStep(
                enMessage: "Excellent. Tutorial completed. Welcome to EduNode!",
                zhMessage: "太好了，教程全部完成。欢迎使用 EduNode！",
                advanceMode: .animationAuto
            ),
        ]
    }

    var body: some View {
        rootView
        .onAppear {
            persistenceLog("ContentView.onAppear files=\(workspaceFiles.count)", force: true)
            if workspaceAgentConversationByFile.isEmpty {
                workspaceAgentConversationByFile = EduAgentConversationPersistence.loadWorkspaceConversations()
            }
            refreshBackendSessionSnapshot()
            resolveStartupAccountGateIfNeeded()
            seedDefaultCourseIfNeeded()
            syncSelectedWorkspaceFile()
            hydratePresentationStateFromStoreIfNeeded()
            migrateWorkspaceFilesIfNeeded()
            requestCameraFocusOnFirstNodeForSelectedFile()
            if !tutorialHintPulsePhase {
                withAnimation(.easeInOut(duration: 0.86).repeatForever(autoreverses: true)) {
                    tutorialHintPulsePhase = true
                }
            }
        }
        .onChange(of: workspaceFiles.map(\.id)) { _, _ in
            syncSelectedWorkspaceFile()
            hydratePresentationStateFromStoreIfNeeded()
            migrateWorkspaceFilesIfNeeded()
            if let activePresentationModeFileID,
               !workspaceFiles.contains(where: { $0.id == activePresentationModeFileID }) {
                self.activePresentationModeFileID = nil
            }
            let existingIDs = Set(workspaceFiles.map(\.id))
            hydratedPresentationStateFileIDs = hydratedPresentationStateFileIDs.intersection(existingIDs)
            presentationStylingTouchedFileIDs = presentationStylingTouchedFileIDs.intersection(existingIDs)
            presentationBreaksByFile = presentationBreaksByFile.filter { existingIDs.contains($0.key) }
            presentationExcludedNodeIDsByFile = presentationExcludedNodeIDsByFile.filter { existingIDs.contains($0.key) }
            selectedPresentationGroupIDByFile = selectedPresentationGroupIDByFile.filter { existingIDs.contains($0.key) }
            presentationStylingByFile = presentationStylingByFile.filter { existingIDs.contains($0.key) }
            presentationPageStyleByFile = presentationPageStyleByFile.filter { existingIDs.contains($0.key) }
            presentationTextThemeByFile = presentationTextThemeByFile.filter { existingIDs.contains($0.key) }
            if let activePresentationStylingFileID,
               !existingIDs.contains(activePresentationStylingFileID) {
                self.activePresentationStylingFileID = nil
            }
            if let presentationModeLoadingFileID,
               !existingIDs.contains(presentationModeLoadingFileID) {
                self.presentationModeLoadingFileID = nil
                self.presentationModeActivationToken = nil
            }
            pendingPresentationThumbnailIDsByFile = pendingPresentationThumbnailIDsByFile.filter { existingIDs.contains($0.key) }
            workspaceAgentConversationByFile = workspaceAgentConversationByFile.filter { existingIDs.contains($0.key) }
            EduAgentConversationPersistence.saveWorkspaceConversations(workspaceAgentConversationByFile)
            requestCameraFocusOnFirstNodeForSelectedFile()
        }
        .onChange(of: selectedFileID) { _, _ in
            isSidebarBasicInfoExpanded = false
            selectedModelTemplatePreviewID = nil
            if workspaceAgentSidebarFileID != nil {
                workspaceAgentSidebarFileID = selectedFileID
            }
            requestCameraFocusOnFirstNodeForSelectedFile()
            handleTutorialSelectionChange()
        }
        .onChange(of: scenePhase) { _, newPhase in
            persistenceLog("scenePhase -> \(String(describing: newPhase))", force: true)
            if newPhase == .active {
                refreshBackendSessionSnapshot()
                resolveStartupAccountGateIfNeeded()
            }
            if newPhase == .inactive || newPhase == .background {
                persistAllPresentationStates()
            }
        }
        .onChange(of: showingCreateCourseSheet) { _, _ in
            handleTutorialSheetStateChange()
        }
        .onChange(of: activePresentationModeFileID) { _, _ in
            handleTutorialPresentationStateChange()
        }
        .onChange(of: activePresentationStylingFileID) { _, _ in
            handleTutorialPresentationStateChange()
        }
        .onChange(of: lessonPlanPreviewPayload?.id) { _, _ in
            handleTutorialPreviewStateChange()
        }
        .onChange(of: presentationPreviewPayload?.id) { _, _ in
            handleTutorialPreviewStateChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: .eduNodeCommandNewCourse)) { _ in
            presentCreateCourseSheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: .eduNodeCommandImportCourse)) { _ in
            showingSidebarImporter = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .eduNodeCommandOpenDocumentation)) { _ in
            showingDocs = true
            handleDocsOpenedDuringTutorial()
        }
        .onReceive(NotificationCenter.default.publisher(for: .eduNodeCommandOpenTutorialGuide)) { _ in
            showingOnboardingGuide = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .eduNodeCommandOpenAccount)) { _ in
            showingAccountSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .eduNodeBackendSessionDidChange)) { _ in
            refreshBackendSessionSnapshot()
        }
    }

    @ViewBuilder
    var rootView: some View {
        if !didResolveStartupAccountGate {
            startupLaunchPlaceholder
        } else if showingStartupAccountGate {
            startupAccountGateView
        } else {
            coreLayout
        }
    }

    var startupLaunchPlaceholder: some View {
        ZStack {
            EduPanelStyle.sheetBackground
            ProgressView()
                .tint(.white)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var startupAccountGateView: some View {
        EduAgentSettingsSheet(
            onSaved: {
                showingStartupAccountGate = false
                didResolveStartupAccountGate = true
                refreshBackendSessionSnapshot()
            },
            allowsContinueWithoutAccount: true,
            onContinueWithoutAccount: {
                showingStartupAccountGate = false
                didResolveStartupAccountGate = true
                refreshBackendSessionSnapshot()
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }

    var coreLayout: some View {
        Group {
            #if targetEnvironment(macCatalyst)
            workspaceChrome(topSafeInset: 0)
                .ignoresSafeArea(.container, edges: .top)
            #else
            GeometryReader { rootGeometry in
                workspaceChrome(topSafeInset: stableWorkspaceTopInset(rootGeometry.safeAreaInsets.top))
            }
            .ignoresSafeArea(.container, edges: .top)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingCreateCourseSheet) {
            CourseCreationSheet(
                draft: $creationDraft,
                modelRules: modelRules,
                onCancel: {
                    showingCreateCourseSheet = false
                },
                onCreate: {
                    createWorkspaceFileFromDraft()
                },
                requiredModelID: activeTutorial == .practice ? tutorialPracticeRequiredModelID : nil
            )
            .frame(minHeight: courseCreationSheetMinHeight)
            .presentationDetents([.large])
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showingStudentRosterEdit) {
            CourseCreationSheet(
                draft: $creationDraft,
                modelRules: modelRules,
                onCancel: {
                    showingStudentRosterEdit = false
                },
                onCreate: {
                    showingStudentRosterEdit = false
                },
                initialPage: .teamStudents,
                onSaveRoster: { newRoster in
                    saveStudentRoster(newRoster)
                }
            )
            .frame(minHeight: courseCreationSheetMinHeight)
            .presentationDetents([.large])
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showingEditCourseSheet) {
            CourseCreationSheet(
                draft: $creationDraft,
                modelRules: modelRules,
                onCancel: {
                    showingEditCourseSheet = false
                },
                onCreate: {
                    saveCourseEdits()
                },
                isEditing: true
            )
            .frame(minHeight: courseCreationSheetMinHeight)
            .presentationDetents([.large])
            .preferredColorScheme(.dark)
        }
        .alert(S("course.modelChangeWarningTitle"), isPresented: $showingModelChangeWarning) {
            Button(S("action.close"), role: .cancel) {}
        } message: {
            Text(S("course.modelChangeWarningMessage"))
        }
        .fileImporter(isPresented: $showingSidebarImporter, allowedContentTypes: [.json, .data]) { result in
            switch result {
            case .success(let url):
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url) {
                    importWorkspaceFile(data: data, suggestedName: url.deletingPathExtension().lastPathComponent)
                }
            case .failure:
                break
            }
        }
        .sheet(
            isPresented: $showingAccountSheet,
            onDismiss: { refreshBackendSessionSnapshot() }
        ) {
            EduAgentSettingsSheet(
                onSaved: {
                    refreshBackendSessionSnapshot()
                }
            )
            .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $showingDocs) {
            docsContent
                .ignoresSafeArea()
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { activePresentationStylingFileID != nil },
                set: { isPresented in
                    if !isPresented {
                        activePresentationStylingFileID = nil
                    }
                }
            )
        ) {
            presentationStylingFullScreenPage
        }
        .sheet(item: $lessonPlanSetupPayload) { payload in
            EduLessonPlanExportSetupSheet(payload: payload) { previewPayload in
                lessonPlanPreviewPayload = previewPayload
            }
        }
        .fullScreenCover(item: $lessonPlanPreviewPayload) { payload in
            EduLessonPlanWorkbenchView(payload: payload)
        }
        .sheet(item: $presentationPreviewPayload) { payload in
            EduPresentationPreviewSheet(payload: payload)
        }
        .alert(S("app.presentation.emptyTitle"), isPresented: $showingPresentationEmptyAlert) {
            Button(S("action.close"), role: .cancel) {}
        } message: {
            Text(S("app.presentation.emptyMessage"))
        }
        .alert(
            pendingFlowStepIsDone ? S("flow.confirm.uncompleteTitle") : S("flow.confirm.completeTitle"),
            isPresented: Binding(
                get: { pendingFlowStepConfirmation != nil },
                set: { isPresented in
                    if !isPresented {
                        clearPendingFlowStepConfirmation()
                    }
                }
            )
        ) {
            Button(pendingFlowStepIsDone ? S("flow.confirm.uncompleteAction") : S("flow.confirm.completeAction")) {
                confirmPendingFlowStep()
            }
            Button(S("action.cancel"), role: .cancel) {
                clearPendingFlowStepConfirmation()
            }
        } message: {
            if let step = pendingFlowStepConfirmation {
                Text(String(format: S("flow.confirm.message"), step.title(S)))
            }
        }
        .fileExporter(
            isPresented: $showingWorkspaceToolbarExporter,
            document: workspaceToolbarExportDocument,
            contentType: workspaceToolbarExportContentType,
            defaultFilename: workspaceToolbarExportFilename
        ) { _ in
            workspaceToolbarExportDocument = nil
        }
    }

    private func workspaceChrome(topSafeInset: CGFloat) -> some View {
        ZStack {
            #if targetEnvironment(macCatalyst)
            HStack(spacing: 0) {
                if splitVisibility != .detailOnly {
                    sidebarView(topInset: topSafeInset)
                        .frame(width: workspaceSidebarColumnWidth)
                        .zIndex(30)

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1)
                        .zIndex(29)
                }

                detailView(toolbarTopPadding: topSafeInset + workspaceTopToolbarPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .zIndex(0)
            }
            .background(Color(white: 0.1))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #else
            NavigationSplitView(columnVisibility: $splitVisibility) {
                sidebarView(topInset: topSafeInset)
                    .navigationSplitViewColumnWidth(
                        min: workspaceSidebarColumnWidth,
                        ideal: workspaceSidebarColumnWidth,
                        max: workspaceSidebarColumnWidth
                    )
            } detail: {
                detailView(toolbarTopPadding: topSafeInset + workspaceTopToolbarPadding)
            }
            .navigationSplitViewStyle(.balanced)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif

            // Custom sidebar toggle (system nav bar is fully hidden to avoid
            // its invisible hit area blocking custom toolbar taps on iPadOS).
            if splitVisibility == .detailOnly {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        sidebarToggleButton
                            .padding(.leading, workspaceSidebarToggleLeadingPadding)
                        Spacer()
                    }
                    .padding(.top, topSafeInset + workspaceTopToolbarPadding)
                    Spacer()
                }
                .ignoresSafeArea(edges: .top)
                .zIndex(5000)
            }

            if presentationModeLoadingFileID != nil {
                presentationPreparingOverlay
                    .zIndex(6000)
            }

            if showingOnboardingGuide {
                onboardingGuideOverlay
                    .zIndex(6100)
            }

            if shouldShowTutorialDesignButtonSpotlight {
                tutorialDesignButtonSpotlightOverlay()
                    .zIndex(6040)
                    .transition(.opacity)
            }

            if activeTutorial != nil
                && !isTutorialInDocsPhase
                && !showingCreateCourseSheet {
                tutorialCoachMarkOverlay
                    .zIndex(6050)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .coordinateSpace(name: tutorialRootCoordinateSpaceName)
    }

    func sidebarView(topInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            if showsSidebarUtilityHeader {
                sidebarHeaderBar(topInset: topInset)
            }

            #if targetEnvironment(macCatalyst)
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(workspaceFiles, id: \.id) { file in
                        Button {
                            selectedFileID = file.id
                        } label: {
                            sidebarFileRow(file)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(selectedFileID == file.id ? Color.accentColor.opacity(0.28) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                deleteWorkspaceFile(file)
                            } label: {
                                Label(S("app.files.delete"), systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .background(sidebarLayoutDebugEnabled ? Color.blue.opacity(0.22) : sidebarChromeBackground)
            #else
            List(selection: $selectedFileID) {
                ForEach(workspaceFiles, id: \.id) { file in
                    sidebarFileRow(file)
                    .tag(file.id as UUID?)
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteWorkspaceFile(file)
                        } label: {
                            Label(S("app.files.delete"), systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteWorkspaceFile(file)
                        } label: {
                            Label(S("app.files.delete"), systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .background(sidebarLayoutDebugEnabled ? Color.blue.opacity(0.22) : Color.clear)
            #endif
        }
        .frame(width: workspaceSidebarColumnWidth)
        .background {
            #if targetEnvironment(macCatalyst)
            sidebarLayoutDebugEnabled ? Color.red.opacity(0.16) : sidebarChromeBackground
            #else
            sidebarLayoutDebugEnabled ? Color.red.opacity(0.16) : Color.clear
            #endif
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func sidebarHeaderBar(topInset: CGFloat) -> some View {
        Group {
            #if targetEnvironment(macCatalyst)
            HStack(spacing: 10) {
                sidebarVisibilityButton(
                    systemImage: "sidebar.left",
                    accessibilityLabel: isChineseUI() ? "隐藏侧栏" : "Hide Sidebar"
                ) {
                    withAnimation { splitVisibility = .detailOnly }
                }

                sidebarAccountButton
                sidebarCommandButtonGroup
                Spacer(minLength: 0)
            }
            .padding(.leading, workspaceSidebarHeaderLeadingPadding)
            .padding(.trailing, 14)
            #else
            HStack(spacing: 0) {
                sidebarVisibilityButton(
                    systemImage: "sidebar.left",
                    accessibilityLabel: isChineseUI() ? "隐藏侧栏" : "Hide Sidebar"
                ) {
                    withAnimation { splitVisibility = .detailOnly }
                }
                .frame(maxWidth: .infinity)

                sidebarAccountButton
                    .frame(maxWidth: .infinity)

                sidebarDocsButton
                    .frame(maxWidth: .infinity)

                sidebarGuideButton
                    .frame(maxWidth: .infinity)

                sidebarCreateMenu
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 10)
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, topInset + workspaceTopToolbarPadding)
        .padding(.bottom, 10)
        .background {
            #if targetEnvironment(macCatalyst)
            sidebarLayoutDebugEnabled ? Color.green.opacity(0.28) : sidebarChromeBackground
            #else
            if sidebarLayoutDebugEnabled {
                Color.green.opacity(0.28)
            } else {
                Color.clear
            }
            #endif
        }
    }

    private var sidebarAccountButton: some View {
        Button {
            showingAccountSheet = true
        } label: {
            sidebarHeaderIconButton(
                systemImage: backendSessionSnapshot == nil
                    ? "person.crop.circle.badge.plus"
                    : "person.crop.circle"
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(backendSessionSnapshot == nil
            ? (isChineseUI() ? "登录" : "Sign In")
            : (isChineseUI() ? "账户" : "Account"))
    }

    private var sidebarDocsButton: some View {
        Button {
            showingDocs = true
            handleDocsOpenedDuringTutorial()
        } label: {
            sidebarHeaderIconButton(systemImage: "book.closed")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(S("app.sidebar.docs"))
    }

    private var sidebarGuideButton: some View {
        Button {
            showingOnboardingGuide = true
        } label: {
            sidebarHeaderIconButton(systemImage: "questionmark.circle")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isChineseUI() ? "说明" : "Guide")
    }

    private var sidebarCreateMenu: some View {
        Menu {
            Button {
                presentCreateCourseSheet()
            } label: {
                Label(S("app.files.newCourse"), systemImage: "plus")
            }

            Button {
                showingSidebarImporter = true
            } label: {
                Label(S("app.files.import"), systemImage: "square.and.arrow.down")
            }
        } label: {
            sidebarHeaderIconButton(systemImage: "plus")
        }
        .menuStyle(.button)
        .accessibilityLabel(S("app.files.newCourse"))
    }

    private var sidebarCommandButtonGroup: some View {
        HStack(spacing: 10) {
            sidebarDocsButton
            sidebarGuideButton
            sidebarCreateMenu
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func sidebarVisibilityButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            sidebarHeaderIconButton(systemImage: systemImage)
        }

        #if targetEnvironment(macCatalyst)
        button
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
        #else
        button
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
        #endif
    }

    @ViewBuilder
    private func sidebarHeaderIconButton(systemImage: String) -> some View {
        let icon = Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .frame(width: workspaceTopToolbarButtonHeight, height: workspaceTopToolbarButtonHeight)

        #if targetEnvironment(macCatalyst)
        icon
            .foregroundStyle(.white.opacity(0.92))
            .background(Color.white.opacity(0.07), in: Circle())
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        #else
        if #available(iOS 26.0, macOS 26.0, *) {
            icon
                .foregroundStyle(.primary)
                .background {
                    Button(action: {}) {
                        Color.clear
                            .frame(width: workspaceTopToolbarButtonHeight, height: workspaceTopToolbarButtonHeight)
                    }
                    .buttonStyle(GlassButtonStyle())
                    .buttonBorderShape(.circle)
                    .allowsHitTesting(false)
                }
                .clipShape(Circle())
        } else {
            icon
                .foregroundStyle(.primary)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        }
        #endif
    }

    private func workspaceTopRightToolbar(file: GNodeWorkspaceFile, topPadding: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: workspaceTopRightToolbarSpacing) {
                Spacer(minLength: 0)

                workspaceTopToolbarButton(
                    title: isChineseUI() ? "清空" : "Clear",
                    systemImage: "trash",
                    accent: .red,
                    width: workspaceTopRightToolbarButtonWidth
                ) {
                    persistWorkspaceFileData(id: file.id, data: emptyDocumentData())
                }

                Menu {
                    Button {
                        prepareWorkspaceToolbarExport(
                            data: file.data,
                            contentType: .json,
                            defaultFilename: "\(sanitizedExportBaseName(file.name)).gnode"
                        )
                    } label: {
                        Label("GNode", systemImage: "link.badge.plus")
                    }

                    ForEach(editorExportActions(for: file), id: \.id) { action in
                        Button {
                            guard let data = action.buildData(file.data) else { return }
                            prepareWorkspaceToolbarExport(
                                data: data,
                                contentType: action.contentType,
                                defaultFilename: action.defaultFilename
                            )
                        } label: {
                            Label(action.title, systemImage: action.systemImage)
                        }
                    }
                } label: {
                    workspaceTopToolbarLabel(
                        title: isChineseUI() ? "导出" : "Export",
                        systemImage: "square.and.arrow.up",
                        accent: .green,
                        width: workspaceTopRightToolbarButtonWidth
                    )
                }
                .buttonStyle(.plain)

                workspaceTopToolbarButton(
                    title: S("app.presentation.button"),
                    systemImage: "play.rectangle.on.rectangle",
                    accent: .orange,
                    width: workspaceTopRightToolbarButtonWidth
                ) {
                    handlePresentationButtonTap(for: file)
                }
            }
            .padding(.top, topPadding)
            .padding(.trailing, workspaceTopRightToolbarTrailingPadding)

            Spacer(minLength: 0)
        }
    }

    private func workspaceTopToolbarButton(
        title: String,
        systemImage: String,
        accent: Color,
        width: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            workspaceTopToolbarLabel(
                title: title,
                systemImage: systemImage,
                accent: accent,
                width: width
            )
        }
        .buttonStyle(.plain)
    }

    private func workspaceTopToolbarLabel(
        title: String,
        systemImage: String,
        accent: Color,
        width: CGFloat
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(accent)

            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 8)
        .frame(width: width, height: workspaceTopToolbarButtonHeight)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private func prepareWorkspaceToolbarExport(
        data: Data,
        contentType: UTType,
        defaultFilename: String
    ) {
        workspaceToolbarExportDocument = EduWorkspaceToolbarExportDocument(data: data)
        workspaceToolbarExportContentType = contentType
        workspaceToolbarExportFilename = defaultFilename
        showingWorkspaceToolbarExporter = true
    }

    private func refreshBackendSessionSnapshot() {
        backendSessionSnapshot = EduBackendSessionStore.load()
    }

    private func resolveStartupAccountGateIfNeeded() {
        guard !didResolveStartupAccountGate else { return }
        showingStartupAccountGate = backendSessionSnapshot == nil
        didResolveStartupAccountGate = true
    }

    @ViewBuilder
    func detailView(toolbarTopPadding: CGFloat) -> some View {
        if let preview = selectedModelTemplatePreview {
            modelTemplatePreviewDetailView(preview, toolbarTopPadding: toolbarTopPadding)
        } else if let file = selectedWorkspaceFile {
            let rawDeck = EduPresentationPlanner.makeDeck(graphData: file.data)
            let deck = filteredPresentationDeck(for: file.id, from: rawDeck)
            let slideGroups = presentationGroups(for: file.id, deck: deck)
            let composedSlides = EduPresentationPlanner.composeSlides(
                from: slideGroups,
                isChinese: isChineseUI()
            )
            let isPresentationModeActive = activePresentationModeFileID == file.id
            let reviewTarget = isPresentationModeActive ? nil : currentWorkspaceAgentReviewTarget(for: file)
            let previewDocumentData = reviewTarget?.previewData
            GeometryReader { detailGeometry in
                ZStack {
                    NodeEditorView(
                        documentID: file.id,
                        documentData: previewDocumentData ?? file.data,
                        toolbarLeadingPadding: 20 + topToolbarLeadingReservedWidth,
                        toolbarTrailingPadding: usesCustomWorkspaceTopToolbar
                            ? workspaceTopRightToolbarReservedWidth
                            : 20,
                        toolbarTopPadding: toolbarTopPadding,
                        showImportButton: false,
                        showClearButton: !isPresentationModeActive && !usesCustomWorkspaceTopToolbar,
                        showExportButton: !isPresentationModeActive && !usesCustomWorkspaceTopToolbar,
                        showStatsOverlay: false,
                        exportActions: editorExportActions(for: file),
                        toolbarActions: usesCustomWorkspaceTopToolbar ? [] : editorToolbarActions(for: file),
                        cameraRequest: cameraRequest,
                        selectionRequest: selectionRequest,
                        customNodeMenuSections: eduNodeMenuSections,
                        topCenterOverlay: isPresentationModeActive
                            ? nil
                            : AnyView(
                                EduFlowProgressView(
                                    states: flowStates(for: file),
                                    onToggleManual: { step in
                                        handleFlowStepTap(step, for: file)
                                    }
                                )
                                .padding(.trailing, 6)
                            ),
                        onStatsChanged: { stats in
                            editorStatsByFileID[file.id] = stats
                            handleTutorialStatsChange(fileID: file.id, stats: stats)
                        },
                        connectionAppearanceProvider: { connection, sourceNodeType, targetNodeType in
                            editorConnectionAppearance(
                                for: connection,
                                sourceNodeType: sourceNodeType,
                                targetNodeType: targetNodeType
                            )
                        },
                        onDocumentDataChange: { data in
                            guard previewDocumentData == nil else { return }
                            persistWorkspaceFileData(id: file.id, data: data)
                        },
                        onNodeSelected: { nodeID in
                            guard activePresentationModeFileID == file.id else { return }
                            let rawDeck = EduPresentationPlanner.makeDeck(graphData: file.data)
                            let deck = filteredPresentationDeck(for: file.id, from: rawDeck)
                            let groups = presentationGroups(for: file.id, deck: deck)
                            if let matched = groups.first(where: { $0.sourceSlides.contains(where: { $0.id == nodeID }) }) {
                                guard selectedPresentationGroupIDByFile[file.id] != matched.id else { return }
                                selectedPresentationGroupIDByFile[file.id] = matched.id
                                persistPresentationState(fileID: file.id)
                            }
                        }
                    )
                    .id(file.id)
                    .ignoresSafeArea(edges: [.top, .bottom])
                    .toolbar(.hidden, for: .navigationBar)

                    if !isPresentationModeActive && usesCustomWorkspaceTopToolbar {
                        workspaceTopRightToolbar(file: file, topPadding: toolbarTopPadding)
                            .zIndex(2450)
                    }

                    if isPresentationModeActive && !slideGroups.isEmpty {
                        presentationTrackingPanel(
                            file: file,
                            groups: slideGroups,
                            topPadding: toolbarTopPadding,
                            graphData: file.data
                        )
                        .zIndex(2100)

                        if activePresentationStylingFileID != file.id {
                            presentationStylingFloatingEntryButton(
                                fileID: file.id,
                                groups: slideGroups
                            )
                            .onPreferenceChange(TutorialDesignButtonFramePreferenceKey.self) { frame in
                                guard frame.width > 1, frame.height > 1 else { return }
                                tutorialDesignButtonFrameInGlobal = frame
                            }
                            .zIndex(2050)
                        }

                        presentationFilmstrip(
                            fileID: file.id,
                            courseName: file.name,
                            deck: deck,
                            groups: slideGroups,
                            slides: composedSlides
                        )
                        .zIndex(2000)
                    }

                    editorStatsOverlay(
                        stats: statsForDisplay(for: file)
                    )
                    .zIndex(2200)

                    if !isPresentationModeActive && !isWorkspaceAgentSidebarVisible(for: file) {
                        EduWorkspaceAgentFloatingButton(
                            isChinese: isChineseUI(),
                            containerSize: detailGeometry.size,
                            safeAreaInsets: detailGeometry.safeAreaInsets
                        ) {
                            openWorkspaceAgent(for: file)
                        }
                        .zIndex(2300)
                    }

                    if isWorkspaceAgentSidebarVisible(for: file) {
                        workspaceAgentSidebar(
                            file: file,
                            availableWidth: detailGeometry.size.width,
                            topPadding: usesCustomWorkspaceTopToolbar
                                ? toolbarTopPadding + workspaceTopToolbarButtonHeight + 14
                                : toolbarTopPadding
                        )
                        .zIndex(2400)
                    }

                    if let reviewTarget {
                        workspaceAgentReviewBar(
                            file: file,
                            target: reviewTarget
                        )
                        .zIndex(2350)
                    }
                }
                .animation(.spring(response: 0.28, dampingFraction: 0.88), value: workspaceAgentSidebarFileID)
            }
            .background(Color(white: 0.1))
        } else {
            ZStack {
                Color(white: 0.1)
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    Text(S("app.files.empty"))
                        .foregroundStyle(.secondary)

                    Button {
                        presentCreateCourseSheet()
                    } label: {
                        Label(S("app.files.newCourse"), systemImage: "plus")
                    }
                }
            }
        }
    }

    func statsForDisplay(for file: GNodeWorkspaceFile) -> NodeEditorCanvasStats {
        if let stats = editorStatsByFileID[file.id] {
            return stats
        }
        let fallbackNodeCount: Int
        if let document = try? decodeDocument(from: file.data) {
            fallbackNodeCount = document.nodes.count
        } else {
            fallbackNodeCount = 0
        }
        return NodeEditorCanvasStats(nodeCount: fallbackNodeCount, connectionCount: 0, zoomPercent: 100)
    }

    @ViewBuilder
    var docsContent: some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            ZStack {
                if let docsPreferredNodeType {
                    EduDocumentationView(
                        selectedNodeType: docsPreferredNodeType,
                        onSelectionChange: { selectedType in
                            handleDocsSelectionDuringTutorial(selectedType)
                        },
                        onClose: {
                            if isTutorialInDocsPhase {
                                endTutorial(completed: false)
                            }
                            showingDocs = false
                            self.docsPreferredNodeType = nil
                        }
                    )
                } else {
                    EduDocumentationView(
                        onSelectionChange: { selectedType in
                            handleDocsSelectionDuringTutorial(selectedType)
                        },
                        onClose: {
                            if isTutorialInDocsPhase {
                                endTutorial(completed: false)
                            }
                            showingDocs = false
                        }
                    )
                }

                // Coach mark overlay for docs-phase tutorials
                if isTutorialInDocsPhase && activeTutorial != nil {
                    tutorialCoachMarkOverlay
                }
            }
        } else {
            Text(S("app.docs.unsupported"))
                .padding()
        }
    }

    @ViewBuilder
    var onboardingGuideOverlay: some View {
        let chinese = isChineseUI()

        ZStack {
            Color.black.opacity(0.56)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                onboardingHeaderSection(chinese: chinese)
                onboardingStepsSection(chinese: chinese)
                onboardingDismissButton(chinese: chinese)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(maxWidth: 560, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(EduPanelStyle.sheetBase)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(EduPanelStyle.cardStroke, lineWidth: 1)
            )
            .padding(.horizontal, 20)
        }
        .allowsHitTesting(true)
    }

    @ViewBuilder
    func onboardingHeaderSection(chinese: Bool) -> some View {
        Text(chinese ? "欢迎使用 EduNode" : "Welcome to EduNode")
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)

        Text(
            chinese
            ? "这是一个专业的教学设计工具。建议按下面 3 步完成首次上手：先学，再练，再探索。"
            : "This is a professional lesson-design tool. Start with this 3-step route: learn, practice, then explore."
        )
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.92))
    }

    @ViewBuilder
    func onboardingStepsSection(chinese: Bool) -> some View {
        VStack(spacing: 10) {
            onboardingStepButton(
            index: 1,
            title: chinese ? "5 分钟入门" : "5-Min Basics",
            detail: chinese
            ? "带读了解 EduNode → 教育模型简介 → 画布操作练习。"
            : "Guided reading → Education Models → Canvas practice.",
            isCompleted: didCompleteBasics
            ) {
                startOnboardingTutorial(.aboutDemo)
            }

            onboardingStepButton(
            index: 2,
            title: chinese ? "实战训练" : "Practice",
            detail: chinese
            ? "自动创建一门科学课程，在生成的画布上填写节点。"
            : "Auto-create a science course, then fill in nodes on the canvas.",
            isCompleted: didCompletePractice
            ) {
                startOnboardingTutorial(.practice)
            }

            onboardingStepButton(
            index: 3,
            title: chinese ? "示例探索" : "Explore Example",
            detail: chinese
            ? "打开内置观鸟案例，参考完整课程结构。"
            : "Open the built-in bird sample to see a complete course.",
            isCompleted: didCompleteExplore
            ) {
                startOnboardingTutorial(.explore)
            }
        }
    }

    @ViewBuilder
    func onboardingDismissButton(chinese: Bool) -> some View {
        HStack {
            Spacer()
            Button {
                dismissOnboardingGuideForNow()
            } label: {
                Text(chinese ? "稍后再看" : "Maybe Later")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, 2)
    }

    func startOnboardingTutorial(_ kind: TutorialKind) {
        showingOnboardingGuide = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            startTutorial(kind)
        }
    }

    @ViewBuilder
    func onboardingStepButton(
        index: Int,
        title: String,
        detail: String,
        isCompleted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isCompleted ? Color.green.opacity(0.95) : Color.white.opacity(0.24))
                        .frame(width: 30, height: 30)
                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("\(index)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isCompleted ? Color.green : .white)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isCompleted ? Color.green.opacity(0.9) : Color.white.opacity(0.42))
                    .padding(.top, 7)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isCompleted ? Color.green.opacity(0.13) : EduPanelStyle.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isCompleted ? Color.green.opacity(0.42) : EduPanelStyle.cardStroke, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tutorial Coach Mark Overlay

    var tutorialCoachMarkOverlay: some View {
        let chinese = isChineseUI()
        let steps = currentTutorialSteps
        let stepCount = steps.count
        let currentStep = tutorialStepIndex < stepCount ? steps[tutorialStepIndex] : nil
        let isLastStep = tutorialStepIndex >= stepCount - 1
        let isTapStep = currentStep?.advanceMode == .tapAnywhere
        let isWaitForModelDoc = currentStep?.advanceMode == .waitForModelDocSelection
        let isAutoDetect = !isTapStep
            && currentStep?.advanceMode != .waitForDocs
            && currentStep?.advanceMode != .waitForModelDocSelection
            && currentStep != nil
        let isWaitForDocs = currentStep?.advanceMode == .waitForDocs
        let isGuidedFillStep = isTutorialPracticeGuidedFillStep
        let isPracticeToolkitCreationStep = currentStep?.advanceMode == .waitForSpecificToolkitConfigured
        let isPracticeStylingEnterStep = currentStep?.advanceMode == .waitForStylingPanelEnter
        let isPracticePresentationExitStepInStyling = currentStep?.advanceMode == .waitForPresentationExit
            && activePresentationStylingFileID != nil
        let isPracticeLessonPlanPreviewStep = currentStep?.advanceMode == .waitForLessonPlanPreview
        let isPracticePPTPreviewStep = currentStep?.advanceMode == .waitForPresentationPreview

        return VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                // Phase title + step counter
                HStack {
                    Text(tutorialPhaseTitle(chinese: chinese))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .textCase(.uppercase)

                    Spacer()

                    Text("\(tutorialStepIndex + 1) / \(stepCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 3)
                        Capsule()
                            .fill(Color.green)
                            .frame(width: geo.size.width * CGFloat(tutorialStepIndex + 1) / CGFloat(max(stepCount, 1)), height: 3)
                    }
                }
                .frame(height: 3)

                // Instruction text
                if let step = currentStep {
                    Text(step.message(chinese: chinese))
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .animation(.easeInOut(duration: 0.2), value: tutorialStepIndex)
                }

                // Buttons
                HStack(spacing: 12) {
                    Button {
                        endTutorial(completed: false)
                    } label: {
                        Text(chinese ? "退出" : "Exit")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if isAutoDetect && !isLastStep && !isGuidedFillStep {
                        HStack(spacing: 4) {
                            ProgressView()
                                .tint(.white.opacity(0.6))
                                .scaleEffect(0.7)
                            Text(chinese ? "等待操作…" : "Waiting…")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }

                    if isWaitForDocs && !isLastStep {
                        HStack(spacing: 4) {
                            Image(systemName: "book.fill")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                            Text(chinese ? "请点击 📖 按钮" : "Tap the 📖 button")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }

                    if isWaitForModelDoc && !isLastStep {
                        HStack(spacing: 4) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                            Text(chinese ? "请在文档左栏点击任一教育模型" : "Select any Education Model in Docs sidebar")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }

                    if isPracticeToolkitCreationStep && !isLastStep {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.tap.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .scaleEffect(tutorialHintPulsePhase ? 1.05 : 0.92)
                            Text(chinese ? "双击画布空白处 → 选择工具节点 → 探究" : "Double-tap empty canvas -> Toolkit -> Inquiry")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }

                    if isPracticeStylingEnterStep && !isLastStep {
                        HStack(spacing: 6) {
                            Image(systemName: "paintpalette.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .scaleEffect(tutorialHintPulsePhase ? 1.05 : 0.92)
                            Text(chinese ? "点击左下角调色盘 Design 按钮" : "Tap the bottom-left palette Design button")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }

                    if isPracticePresentationExitStepInStyling && !isLastStep {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.backward.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .scaleEffect(tutorialHintPulsePhase ? 1.05 : 0.92)
                            Text(chinese ? "先点击左上角 Back 返回，再点 Present 退出演示" : "Tap top-left Back first, then tap Present to exit mode")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }

                    if isPracticeLessonPlanPreviewStep && !isLastStep {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .scaleEffect(tutorialHintPulsePhase ? 1.05 : 0.92)
                            Text(chinese ? "点击右上角 Export → Lesson Plan Preview" : "Tap top-right Export -> Lesson Plan Preview")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }

                    if isPracticePPTPreviewStep && !isLastStep {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .scaleEffect(tutorialHintPulsePhase ? 1.05 : 0.92)
                            Text(chinese ? "点击右上角 Export → PPT Preview" : "Tap top-right Export -> PPT Preview")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }

                    if isGuidedFillStep && !isLastStep {
                        Button {
                            applyTutorialPracticeGuidedFill()
                        } label: {
                            Text(chinese ? "填入教程示例" : "Apply Guided Text")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.orange.opacity(0.9), in: Capsule())
                                .foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)
                    }

                    if isTapStep {
                        Button {
                            if isLastStep {
                                endTutorial(completed: true)
                            } else {
                                advanceTutorialStep()
                            }
                        } label: {
                            Text(isLastStep
                                 ? (chinese ? "完成" : "Done")
                                 : (chinese ? "继续" : "Continue"))
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(Color.accentColor, in: Capsule())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: 420)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .allowsHitTesting(true)
    }

    func tutorialPhaseTitle(chinese: Bool) -> String {
        switch activeTutorial {
        case .aboutDemo: return chinese ? "了解 EduNode" : "About EduNode"
        case .canvasBasics: return chinese ? "基础操作" : "Canvas Basics"
        case .modelsIntro: return chinese ? "教育模型" : "Education Models"
        case .practice: return chinese ? "实战训练" : "Practice"
        case .explore: return chinese ? "示例探索" : "Explore"
        case .none: return ""
        }
    }

    var currentTutorialSteps: [TutorialStep] {
        switch activeTutorial {
        case .aboutDemo: return aboutDemoSteps
        case .canvasBasics: return canvasBasicsSteps
        case .modelsIntro: return modelsIntroSteps
        case .practice: return practiceSteps
        case .explore: return exploreSteps
        case .none: return []
        }
    }

    var currentTutorialAdvanceMode: TutorialAdvanceMode? {
        let steps = currentTutorialSteps
        guard tutorialStepIndex >= 0, tutorialStepIndex < steps.count else { return nil }
        return steps[tutorialStepIndex].advanceMode
    }

    var shouldPulsePresentButton: Bool {
        guard activeTutorial == .practice else { return false }
        let mode = currentTutorialAdvanceMode
        return mode == .waitForPresentationEnter || mode == .waitForPresentationExit
    }

    var shouldPulseDesignEntryButton: Bool {
        guard activeTutorial == .practice else { return false }
        guard currentTutorialAdvanceMode == .waitForStylingPanelEnter else { return false }
        guard let practiceFileID = tutorialPracticeFileID else { return false }
        return activePresentationModeFileID == practiceFileID && activePresentationStylingFileID == nil
    }

    var shouldShowTutorialDesignButtonSpotlight: Bool {
        shouldPulseDesignEntryButton
            && tutorialDesignButtonFrameInGlobal.width > 1
            && tutorialDesignButtonFrameInGlobal.height > 1
    }

    func tutorialDesignButtonSpotlightOverlay() -> some View {
        let localRect = tutorialDesignButtonFrameInGlobal.insetBy(dx: -16, dy: -16)

        return ZStack {
            Color.black.opacity(0.56)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .frame(width: localRect.width, height: localRect.height)
                        .position(x: localRect.midX, y: localRect.midY)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.orange.opacity(tutorialHintPulsePhase ? 0.95 : 0.55), lineWidth: 2.2)
                .frame(width: localRect.width, height: localRect.height)
                .position(x: localRect.midX, y: localRect.midY)

            Text(isChineseUI() ? "Design" : "Design")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.26), lineWidth: 0.8)
                )
                .position(
                    x: localRect.midX,
                    y: max(26, localRect.minY - 20)
                )
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    var isTutorialPracticeGuidedFillStep: Bool {
        guard activeTutorial == .practice else { return false }
        guard tutorialStepIndex < practiceSteps.count else { return false }
        let mode = practiceSteps[tutorialStepIndex].advanceMode
        guard mode == .waitForKnowledgeKeywordEdit || mode == .waitForAdditionalKnowledgeEdit else {
            return false
        }
        return tutorialPracticeAutofillTextForCurrentStep(isChinese: isChineseUI()) != nil
    }

}

struct EduWorkspaceToolbarExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText, .pdf] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
