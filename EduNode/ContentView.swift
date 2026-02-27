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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \GNodeWorkspaceFile.createdAt, order: .forward) private var workspaceFiles: [GNodeWorkspaceFile]
    @AppStorage("edunode.seeded_default_course.v1") private var didSeedDefaultCourse = false
    @AppStorage("edunode.lastPersistLog") private var lastPersistLog = ""
    @AppStorage("edunode.onboarding.completed.v1") private var didCompleteOnboarding = false

    @State private var selectedFileID: UUID?
    @State private var splitVisibility: NavigationSplitViewVisibility = .automatic
    @State private var showingCreateCourseSheet = false
    @State private var creationDraft = CourseCreationDraft()
    @State private var showingStudentRosterEdit = false
    @State private var studentRosterEditFileID: UUID?
    @State private var showingDocs = false
    @State private var docsPreferredNodeType: String?
    @State private var showingOnboardingGuide = false
    @State private var showingSidebarImporter = false
    @State private var lessonPlanPreviewPayload: EduLessonPlanPreviewPayload?
    @State private var presentationPreviewPayload: EduPresentationPreviewPayload?
    @State private var presentationEvaluationSheetContext: PresentationEvaluationSheetContext?
    @State private var showingPresentationEmptyAlert = false
    @State private var activePresentationModeFileID: UUID?
    @State private var activePresentationStylingFileID: UUID?
    @State private var presentationModeLoadingFileID: UUID?
    @State private var presentationModeActivationToken: UUID?
    @State private var pendingPresentationThumbnailIDsByFile: [UUID: Set<UUID>] = [:]
    @State private var presentationBreaksByFile: [UUID: Set<Int>] = [:]
    @State private var presentationExcludedNodeIDsByFile: [UUID: Set<UUID>] = [:]
    @State private var selectedPresentationGroupIDByFile: [UUID: UUID] = [:]
    @State private var presentationStylingByFile: [UUID: [UUID: PresentationSlideStylingState]] = [:]
    @State private var presentationPageStyleByFile: [UUID: PresentationPageStyle] = [:]
    @State private var presentationTextThemeByFile: [UUID: PresentationTextTheme] = [:]
    @State private var hydratedPresentationStateFileIDs: Set<UUID> = []
    @State private var presentationStylingTouchedFileIDs: Set<UUID> = []
    @State private var cameraRequest: NodeEditorCameraRequest?
    @State private var pendingFlowStepConfirmation: EduFlowStep?
    @State private var pendingFlowStepFileID: UUID?
    @State private var pendingFlowStepIsDone = false
    @State private var isSidebarBasicInfoExpanded = false
    @State private var editorStatsByFileID: [UUID: NodeEditorCanvasStats] = [:]
    @State private var initialCameraFocusToken: UUID?
    @State private var modelTemplatePreviewByID: [String: ModelTemplatePreview] = [:]
    @State private var selectedModelTemplatePreviewID: String?
    private let presentationPersistenceDebugEnabled = true

    private let modelRules = EduPlanning.loadModelRules()
    private var eduNodeMenuSections: [NodeMenuSectionConfig] {
        GNodeNodeKit.gnodeNodeKit.canvasMenuSections()
    }

    // When sidebar is hidden, reserve space for the system's circular sidebar reveal button.
    private var topToolbarLeadingReservedWidth: CGFloat {
        splitVisibility == .detailOnly ? 52 : 0
    }
    private let presentationFilmstripHeight: CGFloat = 186

    private struct ResolvedPresentationSelection {
        let group: EduPresentationSlideGroup
        let slide: EduPresentationComposedSlide
    }

    private struct ModelTemplatePreview: Identifiable {
        let id: String
        let modelRuleID: String
        let displayName: String
        let documentID: UUID
        var data: Data
    }

    private enum EvaluationIndicatorKind {
        case score
        case completion
    }

    private struct EvaluationIndicatorDescriptor: Identifiable {
        let id: String
        let name: String
        let kind: EvaluationIndicatorKind
    }

    private struct EvaluationNodeDescriptor: Identifiable {
        let id: UUID
        let title: String
        let indicators: [EvaluationIndicatorDescriptor]
    }

    private struct KnowledgeLevelCountChip: Identifiable {
        let id: String
        let title: String
        let count: Int
    }

    private struct PresentationTrackingSummary {
        let currentPage: Int
        let totalPages: Int
        let levelChips: [KnowledgeLevelCountChip]
        let activeEvaluationNodes: [EvaluationNodeDescriptor]
        let studentNames: [String]
        let isChinese: Bool
    }

    private struct PresentationEvaluationSheetContext: Identifiable {
        let id = UUID()
        let fileName: String
        let evaluationNodes: [EvaluationNodeDescriptor]
        let studentNames: [String]
        let isChinese: Bool
    }

    private struct PresentationEvaluationScoringSheet: View {
        let context: PresentationEvaluationSheetContext

        @Environment(\.dismiss) private var dismiss
        @State private var scoreValues: [ScoreCellKey: String] = [:]
        @State private var completionValues: [ScoreCellKey: Bool] = [:]

        private let nameColumnWidth: CGFloat = 150
        private let metricColumnWidth: CGFloat = 132

        private struct ScoreCellKey: Hashable {
            let nodeID: UUID
            let indicatorID: String
            let studentName: String
        }

        var body: some View {
            NavigationStack {
                VStack(spacing: 0) {
                    if context.studentNames.isEmpty {
                        Text(context.isChinese ? "请先在课程问卷中配置学生名单。" : "Please configure student roster in course form first.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(20)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        ScrollView([.vertical, .horizontal], showsIndicators: true) {
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(context.evaluationNodes) { node in
                                    evaluationSection(for: node)
                                }
                            }
                            .padding(16)
                        }
                    }
                }
                .navigationTitle(context.isChinese ? "课程评价打分" : "Course Evaluation Scoring")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(context.isChinese ? "关闭" : "Close") {
                            dismiss()
                        }
                    }
                }
            }
            .presentationDetents([.large])
            .onAppear {
                initializeCellsIfNeeded()
            }
        }

        @ViewBuilder
        private func evaluationSection(for node: EvaluationNodeDescriptor) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(node.title)
                    .font(.headline.weight(.semibold))

                if node.indicators.isEmpty {
                    Text(context.isChinese ? "当前 Evaluation 节点没有指标，请先在节点中配置指标行。" : "No indicators found in this Evaluation node. Configure indicators in node form first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        headerRow(for: node)
                        ForEach(context.studentNames, id: \.self) { studentName in
                            scoreRow(for: node, studentName: studentName)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                }
            }
        }

        @ViewBuilder
        private func headerRow(for node: EvaluationNodeDescriptor) -> some View {
            HStack(spacing: 8) {
                Text(context.isChinese ? "学生" : "Student")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: nameColumnWidth, alignment: .leading)

                ForEach(node.indicators) { indicator in
                    Text(indicatorHeaderTitle(indicator))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: metricColumnWidth, alignment: .center)
                }
            }
        }

        @ViewBuilder
        private func scoreRow(for node: EvaluationNodeDescriptor, studentName: String) -> some View {
            HStack(spacing: 8) {
                Text(studentName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .frame(width: nameColumnWidth, alignment: .leading)

                ForEach(node.indicators) { indicator in
                    switch indicator.kind {
                    case .score:
                        TextField(
                            context.isChinese ? "0-5" : "0-5",
                            text: scoreBinding(nodeID: node.id, indicatorID: indicator.id, studentName: studentName)
                        )
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: metricColumnWidth)

                    case .completion:
                        completionCell(
                            nodeID: node.id,
                            indicatorID: indicator.id,
                            studentName: studentName
                        )
                        .frame(width: metricColumnWidth)
                    }
                }
            }
        }

        @ViewBuilder
        private func completionCell(
            nodeID: UUID,
            indicatorID: String,
            studentName: String
        ) -> some View {
            let key = ScoreCellKey(nodeID: nodeID, indicatorID: indicatorID, studentName: studentName)
            let isComplete = completionValues[key] ?? false

            HStack(spacing: 4) {
                completionButton(
                    label: "0",
                    isSelected: !isComplete
                ) {
                    completionValues[key] = false
                }

                completionButton(
                    label: "5",
                    isSelected: isComplete
                ) {
                    completionValues[key] = true
                }
            }
        }

        @ViewBuilder
        private func completionButton(
            label: String,
            isSelected: Bool,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.black.opacity(0.88) : Color.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? Color.white.opacity(0.85) : Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
        }

        private func indicatorHeaderTitle(_ indicator: EvaluationIndicatorDescriptor) -> String {
            let suffix: String
            switch indicator.kind {
            case .score:
                suffix = context.isChinese ? "分数 0-5" : "Score 0-5"
            case .completion:
                suffix = context.isChinese ? "完成 0/5" : "Completion 0/5"
            }
            return "\(indicator.name)\n\(suffix)"
        }

        private func scoreBinding(
            nodeID: UUID,
            indicatorID: String,
            studentName: String
        ) -> Binding<String> {
            let key = ScoreCellKey(nodeID: nodeID, indicatorID: indicatorID, studentName: studentName)
            return Binding(
                get: {
                    scoreValues[key] ?? ""
                },
                set: { newValue in
                    let allowed = "0123456789."
                    let filtered = String(newValue.filter { allowed.contains($0) })
                    guard !filtered.isEmpty else {
                        scoreValues[key] = ""
                        return
                    }

                    guard let parsed = Double(filtered) else { return }
                    let clamped = min(5, max(0, parsed))
                    if clamped == floor(clamped) {
                        scoreValues[key] = String(Int(clamped))
                    } else {
                        scoreValues[key] = String(format: "%.1f", clamped)
                    }
                }
            )
        }

        private func initializeCellsIfNeeded() {
            guard scoreValues.isEmpty && completionValues.isEmpty else { return }

            for node in context.evaluationNodes {
                for indicator in node.indicators {
                    for student in context.studentNames {
                        let key = ScoreCellKey(
                            nodeID: node.id,
                            indicatorID: indicator.id,
                            studentName: student
                        )
                        switch indicator.kind {
                        case .score:
                            scoreValues[key] = "0"
                        case .completion:
                            completionValues[key] = false
                        }
                    }
                }
            }
        }
    }

    var body: some View {
        coreLayout
        .onAppear {
            persistenceLog("ContentView.onAppear files=\(workspaceFiles.count)", force: true)
            seedDefaultCourseIfNeeded()
            syncSelectedWorkspaceFile()
            hydratePresentationStateFromStoreIfNeeded()
            migrateWorkspaceFilesIfNeeded()
            requestCameraFocusOnFirstNodeForSelectedFile()
            if !didCompleteOnboarding {
                showingOnboardingGuide = true
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
            requestCameraFocusOnFirstNodeForSelectedFile()
        }
        .onChange(of: selectedFileID) { _, _ in
            isSidebarBasicInfoExpanded = false
            selectedModelTemplatePreviewID = nil
            requestCameraFocusOnFirstNodeForSelectedFile()
        }
        .onChange(of: scenePhase) { _, newPhase in
            persistenceLog("scenePhase -> \(String(describing: newPhase))", force: true)
            if newPhase == .inactive || newPhase == .background {
                persistAllPresentationStates()
            }
        }
    }

    private var coreLayout: some View {
        GeometryReader { rootGeometry in
            ZStack {
                NavigationSplitView(columnVisibility: $splitVisibility) {
                    sidebarView
                } detail: {
                    let topToolbarPadding = rootGeometry.safeAreaInsets.top + (splitVisibility == .detailOnly ? 0 : 8)
                    detailView(
                        toolbarTopPadding: topToolbarPadding
                    )
                }
                .navigationSplitViewStyle(.balanced)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if presentationModeLoadingFileID != nil {
                    presentationPreparingOverlay
                        .zIndex(6000)
                }

                if showingOnboardingGuide {
                    onboardingGuideOverlay
                        .zIndex(6100)
                }
            }
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
                }
            )
            .presentationDetents([.large])
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
            .presentationDetents([.large])
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
        .sheet(item: $lessonPlanPreviewPayload) { payload in
            EduLessonPlanPreviewSheet(payload: payload)
        }
        .sheet(item: $presentationPreviewPayload) { payload in
            EduPresentationPreviewSheet(payload: payload)
        }
        .sheet(item: $presentationEvaluationSheetContext) { context in
            PresentationEvaluationScoringSheet(context: context)
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
    }

    private var sidebarView: some View {
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
        .navigationTitle(S("app.files.title"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingDocs = true
                } label: {
                    Label(S("app.sidebar.docs"), systemImage: "book.closed")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentCreateCourseSheet()
                } label: {
                    Label(S("app.files.newCourse"), systemImage: "plus")
                }
                .contextMenu {
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
                }
            }
        }
    }

    @ViewBuilder
    private func detailView(toolbarTopPadding: CGFloat) -> some View {
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
            ZStack {
                NodeEditorView(
                    documentID: file.id,
                    documentData: file.data,
                    toolbarLeadingPadding: 20 + topToolbarLeadingReservedWidth,
                    toolbarTrailingPadding: 20,
                    toolbarTopPadding: toolbarTopPadding,
                    showImportButton: false,
                    showStatsOverlay: false,
                    exportActions: editorExportActions(for: file),
                    toolbarActions: editorToolbarActions(for: file),
                    cameraRequest: cameraRequest,
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
                    },
                    connectionAppearanceProvider: { connection, sourceNodeType, targetNodeType in
                        editorConnectionAppearance(
                            for: connection,
                            sourceNodeType: sourceNodeType,
                            targetNodeType: targetNodeType
                        )
                    },
                    onDocumentDataChange: { data in
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
                .toolbarBackground(.hidden, for: .navigationBar)

                if isPresentationModeActive && !slideGroups.isEmpty {
                    presentationTrackingPanel(
                        file: file,
                        groups: slideGroups,
                        topPadding: toolbarTopPadding
                    )
                    .zIndex(2100)

                    if activePresentationStylingFileID != file.id {
                        presentationStylingFloatingEntryButton(
                            fileID: file.id,
                            groups: slideGroups
                        )
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

    private func statsForDisplay(for file: GNodeWorkspaceFile) -> NodeEditorCanvasStats {
        if let stats = editorStatsByFileID[file.id] {
            return stats
        }
        let fallbackNodeCount: Int
        if let document = try? decodeDocument(from: file.data) {
            fallbackNodeCount = document.nodes.count
        } else {
            fallbackNodeCount = 0
        }
        return NodeEditorCanvasStats(nodeCount: fallbackNodeCount, zoomPercent: 100)
    }

    @ViewBuilder
    private var docsContent: some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            if let docsPreferredNodeType {
                NodeDocumentationView(
                    selectedNodeType: docsPreferredNodeType,
                    onClose: {
                        showingDocs = false
                        self.docsPreferredNodeType = nil
                    }
                )
            } else {
                NodeDocumentationView(onClose: {
                    showingDocs = false
                })
            }
        } else {
            Text(S("app.docs.unsupported"))
                .padding()
        }
    }

    @ViewBuilder
    private var onboardingGuideOverlay: some View {
        let chinese = isChineseUI()

        ZStack {
            Color.black.opacity(0.56)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
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

                onboardingStepRow(
                    index: 1,
                    title: chinese ? "5 分钟基础教程" : "5-min Basics",
                    detail: chinese
                    ? "了解课程框架、节点角色与连线规则。"
                    : "Learn framework, node roles, and connection rules."
                )

                onboardingStepRow(
                    index: 2,
                    title: chinese ? "实战训练：中学物理微课" : "Practice: Physics Micro-Lesson",
                    detail: chinese
                    ? "从 Course Context 到 Knowledge/Toolkit 串联，完成讲义与演讲产出。"
                    : "Build Course Context -> Knowledge/Toolkit chain, then finish lesson-plan and presentation output."
                )

                onboardingStepRow(
                    index: 3,
                    title: chinese ? "示例探索" : "Explore Example",
                    detail: chinese
                    ? "先参考内置观鸟案例，再迁移到你自己的主题。"
                    : "Inspect the built-in bird sample, then adapt it to your own topic."
                )

                VStack(spacing: 8) {
                    Button {
                        docsPreferredNodeType = "EduGuideBasics5Min"
                        showingDocs = true
                        completeOnboardingGuide()
                    } label: {
                        Text(chinese ? "开始基础教程" : "Start Basics Tutorial")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        createPhysicsMicroLessonTrainingFile()
                        completeOnboardingGuide()
                    } label: {
                        Text(chinese ? "创建中学物理实战任务" : "Create Physics Practice Task")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.bordered)

                    Button(chinese ? "稍后再看" : "Maybe Later") {
                        dismissOnboardingGuideForNow()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.76))
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(maxWidth: 640, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .padding(.horizontal, 20)
        }
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private func onboardingStepRow(index: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.black.opacity(0.78))
                .frame(width: 18, height: 18)
                .background(Color.white.opacity(0.86), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.84))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var presentationStylingFullScreenPage: some View {
        if let fileID = activePresentationStylingFileID,
           let file = workspaceFiles.first(where: { $0.id == fileID }) {
            GeometryReader { geometry in
                let rawDeck = EduPresentationPlanner.makeDeck(graphData: file.data)
                let deck = filteredPresentationDeck(for: file.id, from: rawDeck)
                let groups = presentationGroups(for: file.id, deck: deck)
                let slides = EduPresentationPlanner.composeSlides(
                    from: groups,
                    isChinese: isChineseUI()
                )
                let selectedPresentation = resolvedPresentationSelection(
                    fileID: file.id,
                    groups: groups,
                    slides: slides
                )

                ZStack {
                    Color(white: 0.1).ignoresSafeArea()

                    if let selectedPresentation {
                        presentationStylingOverlay(
                            file: file,
                            selectedGroup: selectedPresentation.group,
                            selectedSlide: selectedPresentation.slide,
                            toolbarTopPadding: geometry.safeAreaInsets.top,
                            bottomSafeInset: geometry.safeAreaInsets.bottom
                        )

                        if !groups.isEmpty {
                            presentationFilmstrip(
                                fileID: file.id,
                                courseName: file.name,
                                deck: deck,
                                groups: groups,
                                slides: slides
                            )
                            .zIndex(2000)
                        }
                    } else {
                        VStack(spacing: 12) {
                            Text(S("app.presentation.emptyMessage"))
                                .foregroundStyle(.secondary)
                            Button(S("action.close")) {
                                activePresentationStylingFileID = nil
                            }
                        }
                    }
                }
            }
            .ignoresSafeArea()
        } else {
            Color(white: 0.1)
                .ignoresSafeArea()
                .onAppear {
                    activePresentationStylingFileID = nil
                }
        }
    }

    private var selectedWorkspaceFile: GNodeWorkspaceFile? {
        if let selectedFileID {
            return workspaceFiles.first(where: { $0.id == selectedFileID })
        }
        return workspaceFiles.first
    }

    private var selectedModelTemplatePreview: ModelTemplatePreview? {
        guard let selectedModelTemplatePreviewID else { return nil }
        return modelTemplatePreviewByID[selectedModelTemplatePreviewID]
    }

    private func presentCreateCourseSheet() {
        creationDraft = CourseCreationDraft()
        showingCreateCourseSheet = true
    }

    private func showModelTemplatePreview(_ rule: EduModelRule) {
        let chinese = isChineseUI()
        if modelTemplatePreviewByID[rule.id] == nil {
            let draft = modelTemplatePreviewDraft(for: rule, isChinese: chinese)
            let data = EduPlanning.makeInitialDocumentData(
                draft: draft,
                modelRule: rule,
                isChinese: chinese
            )
            modelTemplatePreviewByID[rule.id] = ModelTemplatePreview(
                id: rule.id,
                modelRuleID: rule.id,
                displayName: rule.displayName(isChinese: chinese),
                documentID: UUID(),
                data: data
            )
        }

        selectedModelTemplatePreviewID = rule.id
        activePresentationModeFileID = nil
        activePresentationStylingFileID = nil
        presentationModeLoadingFileID = nil
    }

    private func modelTemplatePreviewDraft(for rule: EduModelRule, isChinese: Bool) -> CourseCreationDraft {
        var draft = CourseCreationDraft()
        let hintText = rule.gradeHints.joined(separator: " ").lowercased()
        if hintText.contains("elementary") || hintText.contains("小学") {
            draft.gradeMinText = "3"
            draft.gradeMaxText = "5"
        } else if hintText.contains("high") || hintText.contains("高中") {
            draft.gradeMinText = "10"
            draft.gradeMaxText = "11"
        } else {
            draft.gradeMinText = "7"
            draft.gradeMaxText = "9"
        }

        draft.courseName = isChinese
            ? "\(rule.displayName(isChinese: true)) 模板预览"
            : "\(rule.displayName(isChinese: false)) Template Preview"
        draft.subject = previewSubject(for: rule, isChinese: isChinese)
        draft.lessonDurationMinutesText = "45"
        draft.studentCountText = "30"
        draft.priorAssessmentScoreText = "70"
        draft.assignmentCompletionRateText = "75"
        draft.supportNeedCountText = "4"
        draft.studentSupportNotes = isChinese
            ? "用于查看该模型的默认节点结构与连线。"
            : "Used to inspect default node structure and connections for this model."
        draft.goals = [
            rule.templateFocus(isChinese: isChinese),
            isChinese ? "检查每个节点输入输出与串联关系。" : "Review each node's IO and chaining."
        ]
        draft.modelID = rule.id
        draft.leadTeacherCountText = "1"
        draft.assistantTeacherCountText = "1"
        draft.teacherRolePlan = isChinese
            ? "主讲：讲解模型结构；助教：记录改进建议。"
            : "Lead: explain model structure; TA: capture improvement notes."
        draft.resourceConstraints = isChinese
            ? "临时预览，不用于正式课堂。"
            : "Temporary preview only, not a production lesson plan."
        return draft
    }

    private func previewSubject(for rule: EduModelRule, isChinese: Bool) -> String {
        let hints = rule.subjectHints.map { $0.lowercased() }
        if hints.contains(where: { $0.contains("math") }) {
            return isChinese ? "数学" : "Mathematics"
        }
        if hints.contains(where: { $0.contains("history") || $0 == "文" }) {
            return isChinese ? "历史" : "History"
        }
        if hints.contains(where: { $0.contains("language") || $0.contains("语文") }) {
            return isChinese ? "语文" : "Language Arts"
        }
        if hints.contains(where: { $0.contains("science") || $0.contains("lab") || $0.contains("理") }) {
            return isChinese ? "科学" : "Science"
        }
        return isChinese ? "综合实践" : "Integrated Practice"
    }

    @ViewBuilder
    private func sidebarModelTemplatePreviewRow(rule: EduModelRule) -> some View {
        let chinese = isChineseUI()
        let isSelected = selectedModelTemplatePreviewID == rule.id
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSelected ? "square.grid.3x3.fill" : "square.grid.3x3")
                .foregroundStyle(isSelected ? .cyan : .secondary)
                .font(.body.weight(.semibold))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.displayName(isChinese: chinese))
                    .font(isSelected ? .body.weight(.semibold) : .body)
                    .lineLimit(1)
                Text(rule.templateFocus(isChinese: chinese))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isSelected {
                Text(chinese ? "预览中" : "Preview")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.cyan)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func modelTemplatePreviewDetailView(
        _ preview: ModelTemplatePreview,
        toolbarTopPadding: CGFloat
    ) -> some View {
        NodeEditorView(
            documentID: preview.documentID,
            documentData: preview.data,
            toolbarLeadingPadding: 20 + topToolbarLeadingReservedWidth,
            toolbarTrailingPadding: 20,
            toolbarTopPadding: toolbarTopPadding,
            showImportButton: false,
            showStatsOverlay: false,
            exportActions: [],
            toolbarActions: [],
            cameraRequest: cameraRequest,
            customNodeMenuSections: eduNodeMenuSections,
            topCenterOverlay: AnyView(
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.3x3.fill")
                    Text(
                        isChineseUI()
                        ? "模型模板预览：\(preview.displayName)"
                        : "Template Preview: \(preview.displayName)"
                    )
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            ),
            connectionAppearanceProvider: { connection, sourceNodeType, targetNodeType in
                editorConnectionAppearance(
                    for: connection,
                    sourceNodeType: sourceNodeType,
                    targetNodeType: targetNodeType
                )
            },
            onDocumentDataChange: { data in
                guard var cached = modelTemplatePreviewByID[preview.modelRuleID] else { return }
                cached.data = data
                modelTemplatePreviewByID[preview.modelRuleID] = cached
            }
        )
        .id(preview.documentID)
        .ignoresSafeArea(edges: [.top, .bottom])
        .toolbarBackground(.hidden, for: .navigationBar)
        .background(Color(white: 0.1))
    }

    private func createWorkspaceFileFromDraft() {
        guard creationDraft.isValid else { return }
        let isChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        let selectedRule = modelRules.first(where: { $0.id == creationDraft.modelID }) ?? modelRules.first

        let data: Data
        if let selectedRule {
            data = EduPlanning.makeInitialDocumentData(
                draft: creationDraft,
                modelRule: selectedRule,
                isChinese: isChinese
            )
        } else {
            data = emptyDocumentData()
        }

        let file = GNodeWorkspaceFile(
            name: creationDraft.courseName,
            data: data,
            gradeLevel: creationDraft.gradeLevelSummary,
            gradeMode: creationDraft.gradeInputMode.rawValue,
            gradeMin: creationDraft.normalizedGradeRange.0,
            gradeMax: creationDraft.normalizedGradeRange.1,
            subject: creationDraft.subject,
            lessonDurationMinutes: creationDraft.lessonDurationMinutes,
            allowOvertime: false,
            periodRange: creationDraft.periodRange,
            studentCount: creationDraft.studentCount,
            studentProfile: creationDraft.studentProfileSummary,
            studentPriorKnowledgeLevel: "\(creationDraft.priorAssessmentScore)",
            studentMotivationLevel: "\(creationDraft.assignmentCompletionRate)",
            studentSupportNotes: creationDraft.studentSupportNotes,
            goalsText: creationDraft.goalsText,
            modelID: creationDraft.modelID,
            teacherTeam: creationDraft.teacherTeamSummary,
            leadTeacherCount: creationDraft.leadTeacherCount,
            assistantTeacherCount: creationDraft.assistantTeacherCount,
            teacherRolePlan: creationDraft.teacherRolePlan,
            learningScenario: "",
            curriculumStandard: "",
            resourceConstraints: creationDraft.resourceConstraints,
            knowledgeToolkitMarkedDone: false,
            lessonPlanMarkedDone: false,
            evaluationMarkedDone: false
        )

        modelContext.insert(file)
        try? modelContext.save()

        selectedFileID = file.id
        showingCreateCourseSheet = false
    }

    private func completeOnboardingGuide() {
        showingOnboardingGuide = false
        didCompleteOnboarding = true
    }

    private func dismissOnboardingGuideForNow() {
        showingOnboardingGuide = false
    }

    private func createPhysicsMicroLessonTrainingFile() {
        let chinese = isChineseUI()
        var draft = CourseCreationDraft()
        draft.courseName = chinese ? "中学物理微课（新手训练）" : "Junior Physics Micro-Lesson (Training)"
        draft.gradeInputMode = .grade
        draft.gradeMinText = "7"
        draft.gradeMaxText = "8"
        draft.subject = chinese ? "物理" : "Physics"
        draft.lessonDurationMinutesText = "20"
        draft.periodRange = chinese ? "新手实战训练 · 20 分钟微课" : "Guided onboarding drill · 20-min micro lesson"
        draft.studentCountText = "32"
        draft.priorAssessmentScoreText = "68"
        draft.assignmentCompletionRateText = "74"
        draft.supportNeedCountText = "6"
        draft.studentSupportNotes = chinese
            ? "关注实验操作安全与分层提问支持。"
            : "Prioritize lab safety and tiered questioning support."
        draft.goals = chinese
            ? [
                "理解力、速度、加速度之间的基本关系。",
                "能够从观测数据中提出解释并进行简短表达。",
                "完成一个 Knowledge -> Toolkit -> Knowledge 的课堂活动链。"
            ]
            : [
                "Understand the core relation among force, speed, and acceleration.",
                "Explain observations using collected data.",
                "Build one classroom chain: Knowledge -> Toolkit -> Knowledge."
            ]
        draft.modelID = modelRules.first(where: { $0.id == "fivee" })?.id ?? (modelRules.first?.id ?? "")
        draft.leadTeacherCountText = "1"
        draft.assistantTeacherCountText = "1"
        draft.teacherRolePlan = chinese
            ? "主讲负责提问与归纳；助教负责器材与巡视反馈。"
            : "Lead teacher handles questioning/synthesis; TA handles equipment and live support."
        draft.resourceConstraints = chinese
            ? "器材：小车、轨道、秒表；场地限制 20 分钟。"
            : "Resources: cart, track, stopwatch; constrained to a 20-minute session."

        creationDraft = draft
        createWorkspaceFileFromDraft()
        requestCameraFocusOnFirstNodeForSelectedFile()
    }

    private func seedDefaultCourseIfNeeded() {
        guard !didSeedDefaultCourse else { return }
        let descriptor = FetchDescriptor<GNodeWorkspaceFile>()
        if let existing = try? modelContext.fetch(descriptor), !existing.isEmpty {
            didSeedDefaultCourse = true
            return
        }

        let isChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        let name = isChinese ? "珠海观鸟美育工作坊" : "Zhuhai Bird & Nest Workshop"
        let subject = isChinese ? "综合实践（美育）" : "Integrated Practice (Aesthetic Education)"
        let goals = zhuhaiSampleGoals(isChinese: isChinese)

        let file = GNodeWorkspaceFile(
            name: name,
            data: EduPlanning.makeZhuhaiBirdSampleDocumentData(isChinese: isChinese),
            gradeLevel: "age 6-13",
            gradeMode: "age",
            gradeMin: 6,
            gradeMax: 13,
            subject: subject,
            lessonDurationMinutes: 120,
            allowOvertime: false,
            periodRange: isChinese ? "2025-12-20 · 珠海市那洲村" : "2025-12-20 · Nazhou Village, Zhuhai",
            studentCount: 28,
            studentProfile: isChinese ? "三年龄段混龄分组（低龄/中龄/高龄）" : "Three mixed age bands (younger/mid/older)",
            studentPriorKnowledgeLevel: "60",
            studentMotivationLevel: "85",
            studentSupportNotes: isChinese ? "低龄组增加助教支持与结构示范。" : "Provide extra TA support and structure demo for younger groups.",
            goalsText: goals,
            modelID: "fivee",
            teacherTeam: isChinese ? "主讲1 + 助教4" : "Lead teacher 1 + TAs 4",
            leadTeacherCount: 1,
            assistantTeacherCount: 4,
            teacherRolePlan: isChinese ? "主讲负责主线与讲授；助教分组支持搭建、记录与安全。" : "Lead teacher drives main instruction; TAs support group build, recording, and safety.",
            learningScenario: "",
            curriculumStandard: "",
            resourceConstraints: "",
            knowledgeToolkitMarkedDone: true,
            lessonPlanMarkedDone: false,
            evaluationMarkedDone: false
        )

        modelContext.insert(file)
        try? modelContext.save()
        selectedFileID = file.id
        didSeedDefaultCourse = true
    }

    private func syncSelectedWorkspaceFile() {
        guard !workspaceFiles.isEmpty else {
            selectedFileID = nil
            return
        }

        if let selectedFileID,
           workspaceFiles.contains(where: { $0.id == selectedFileID }) {
            return
        }

        selectedFileID = workspaceFiles.first?.id
    }

    private func requestCameraFocusOnFirstNodeForSelectedFile() {
        guard let file = selectedWorkspaceFile,
              let firstNodePosition = firstCanvasNodePosition(from: file.data) else {
            return
        }
        guard selectedFileID == file.id else { return }

        let focusToken = UUID()
        initialCameraFocusToken = focusToken
        cameraRequest = NodeEditorCameraRequest(canvasPosition: firstNodePosition)

        Task { @MainActor in
            for delay in [120_000_000, 360_000_000] {
                try? await Task.sleep(nanoseconds: UInt64(delay))
                guard initialCameraFocusToken == focusToken,
                      selectedFileID == file.id else { return }
                cameraRequest = NodeEditorCameraRequest(canvasPosition: firstNodePosition)
            }
        }
    }

    private func firstCanvasNodePosition(from graphData: Data) -> CGPoint? {
        guard let document = try? decodeDocument(from: graphData) else { return nil }
        guard !document.nodes.isEmpty else { return nil }

        struct PositionedNode {
            let id: UUID
            let position: CGPoint
        }
        struct Column {
            var anchorX: CGFloat
            var members: [PositionedNode]
        }

        let stateByNodeID = Dictionary(uniqueKeysWithValues: document.canvasState.map { ($0.nodeID, $0) })
        let nodes: [PositionedNode] = document.nodes.map { serialized in
            let state = stateByNodeID[serialized.id]
            let x = CGFloat(state?.positionX ?? 200)
            let y = CGFloat(state?.positionY ?? 200)
            return PositionedNode(id: serialized.id, position: CGPoint(x: x, y: y))
        }
        guard !nodes.isEmpty else { return nil }

        let sortedByX = nodes.sorted { lhs, rhs in
            if lhs.position.x == rhs.position.x {
                return lhs.position.y < rhs.position.y
            }
            return lhs.position.x < rhs.position.x
        }

        let columnThreshold: CGFloat = 240
        var columns: [Column] = []

        for node in sortedByX {
            if let candidateIndex = columns.firstIndex(where: { abs(node.position.x - $0.anchorX) <= columnThreshold }) {
                columns[candidateIndex].members.append(node)
                let xs = columns[candidateIndex].members.map(\.position.x)
                columns[candidateIndex].anchorX = xs.reduce(0, +) / CGFloat(xs.count)
            } else {
                columns.append(Column(anchorX: node.position.x, members: [node]))
            }
        }

        columns.sort { $0.anchorX < $1.anchorX }
        let ordered = columns.flatMap { column in
            column.members.sorted { lhs, rhs in
                if lhs.position.y == rhs.position.y {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.position.y < rhs.position.y
            }
        }
        return ordered.first?.position
    }

    private func migrateWorkspaceFilesIfNeeded() {
        var didChange = false
        for file in workspaceFiles {
            if let migratedData = EduPlanning.migrateLegacyKnowledgeInputsAndSampleConnectionsIfNeeded(data: file.data),
               migratedData != file.data {
                file.data = migratedData
                file.updatedAt = .now
                didChange = true
            }

            if EduPlanning.isZhuhaiSampleData(file.data), !file.knowledgeToolkitMarkedDone {
                file.knowledgeToolkitMarkedDone = true
                file.updatedAt = .now
                didChange = true
            }

            if EduPlanning.isZhuhaiSampleData(file.data),
               shouldUpgradeZhuhaiGoals(for: file) {
                file.goalsText = zhuhaiSampleGoals(isChinese: inferredChinesePreference(for: file))
                file.updatedAt = .now
                didChange = true
            }
        }
        if didChange {
            try? modelContext.save()
        }
    }

    private func hydratePresentationStateFromStoreIfNeeded() {
        for file in workspaceFiles {
            hydratePresentationState(for: file, force: false)
        }
    }

    private func hydratePresentationState(for file: GNodeWorkspaceFile, force: Bool) {
        if !force, hydratedPresentationStateFileIDs.contains(file.id) {
            return
        }

        let candidatePayloads = presentationStateDecodeCandidates(for: file)
        guard !candidatePayloads.isEmpty else {
            if force {
                persistenceLog("⚠️ No persisted presentation candidate for file \(file.id)", force: true)
            }
            return
        }

        let decoder = JSONDecoder()
        var decodedCandidates: [(source: String, data: Data, payload: PresentationPersistedState)] = []
        var decodeFailures: [String] = []
        for candidate in candidatePayloads {
            do {
                let payload = try decoder.decode(PresentationPersistedState.self, from: candidate.data)
                decodedCandidates.append((candidate.source, candidate.data, payload))
            } catch {
                decodeFailures.append("\(candidate.source): \(error)")
            }
        }

        guard let chosen = preferredPresentationPersistedCandidate(decodedCandidates) else {
            persistenceLog(
                "⚠️ Failed to decode presentation state for file \(file.id). " +
                decodeFailures.joined(separator: " | "),
                force: true
            )
            return
        }
        let persisted = chosen.payload
        let decodedSource = chosen.source

        // Sidecar is authoritative; keep inline payload as compact marker.
        if decodedSource == "sidecar" {
            let markerData = presentationStateInlineMarkerData(fileID: file.id)
            if file.presentationStateData != markerData {
                file.presentationStateData = markerData
                file.updatedAt = .now
                do {
                    try modelContext.save()
                } catch {
                    persistenceLog("⚠️ Failed to persist sidecar marker inline for file \(file.id): \(error)", force: true)
                }
            }
        }

        if !persisted.breaks.isEmpty {
            presentationBreaksByFile[file.id] = Set(persisted.breaks)
        }
        if !persisted.excludedNodeIDs.isEmpty {
            presentationExcludedNodeIDsByFile[file.id] = Set(persisted.excludedNodeIDs)
        }

        let rawDeck = EduPresentationPlanner.makeDeck(graphData: file.data)
        let filteredDeck = filteredPresentationDeck(for: file.id, from: rawDeck)
        let currentGroups = presentationGroups(for: file.id, deck: filteredDeck)
        let currentGroupIDs = Set(currentGroups.map(\.id))
        if let selectedGroupID = persisted.selectedGroupID,
           currentGroupIDs.contains(selectedGroupID) {
            selectedPresentationGroupIDByFile[file.id] = selectedGroupID
        } else if let selectedSignature = persisted.selectedGroupSignature,
                  let matchedGroupID = currentGroups.first(where: { presentationGroupSignature($0) == selectedSignature })?.id {
            selectedPresentationGroupIDByFile[file.id] = matchedGroupID
        }

        presentationPageStyleByFile[file.id] = persisted.pageStyle
        presentationTextThemeByFile[file.id] = persisted.textTheme

        if !persisted.groups.isEmpty {
            presentationStylingByFile[file.id] = remappedPresentationGroupStates(
                fileID: file.id,
                graphData: file.data,
                persistedGroups: persisted.groups,
                pageStyle: persisted.pageStyle,
                textTheme: persisted.textTheme
            )
        }

        let hydratedOverlayCount = (presentationStylingByFile[file.id] ?? [:]).values.reduce(0) { partialResult, state in
            partialResult + state.overlays.count
        }
        persistenceLog(
            "📥 Hydrated presentation state file=\(file.id) source=\(decodedSource) " +
            "persistedGroups=\(persisted.groups.count) hydratedOverlays=\(hydratedOverlayCount) bytes=\(chosen.data.count)"
        )

        hydratedPresentationStateFileIDs.insert(file.id)
    }

    private func persistAllPresentationStates() {
        for file in workspaceFiles {
            persistPresentationState(fileID: file.id)
        }
    }

    private func persistPresentationState(fileID: UUID) {
        guard let file = workspaceFiles.first(where: { $0.id == fileID }) else { return }
        let rawDeck = EduPresentationPlanner.makeDeck(graphData: file.data)
        let filteredDeck = filteredPresentationDeck(for: fileID, from: rawDeck)
        let orderedGroups = presentationGroups(for: fileID, deck: filteredDeck)
        let orderedGroupIDs = orderedGroups.map(\.id)
        let groupSignatureByID = Dictionary(
            uniqueKeysWithValues: orderedGroups.map { group in
                (group.id, presentationGroupSignature(group))
            }
        )
        let stateByGroup = presentationStylingByFile[fileID] ?? [:]
        var orderedPersistedGroups: [PresentationPersistedGroupState] = []

        for groupID in orderedGroupIDs {
            guard let state = stateByGroup[groupID] else { continue }
            orderedPersistedGroups.append(
                PresentationPersistedGroupState(
                    groupID: groupID,
                    groupSignature: groupSignatureByID[groupID],
                    selectedOverlayID: state.selectedOverlayID,
                    vectorization: state.vectorization,
                    nativeTextOverrides: Dictionary(
                        uniqueKeysWithValues: state.nativeTextOverrides.map { key, value in
                            (key.rawValue, value)
                        }
                    ),
                    nativeContentOverrides: Dictionary(
                        uniqueKeysWithValues: state.nativeContentOverrides.map { key, value in
                            (key.rawValue, value)
                        }
                    ),
                    nativeLayoutOverrides: Dictionary(
                        uniqueKeysWithValues: state.nativeLayoutOverrides.map { key, value in
                            (key.rawValue, value)
                        }
                    ),
                    overlays: state.overlays.map(presentationOverlayRecord(from:))
                )
            )
        }

        let remainingGroupIDs = stateByGroup.keys
            .filter { !orderedGroupIDs.contains($0) }
            .sorted { $0.uuidString < $1.uuidString }
        for groupID in remainingGroupIDs {
            guard let state = stateByGroup[groupID] else { continue }
            orderedPersistedGroups.append(
                PresentationPersistedGroupState(
                    groupID: groupID,
                    groupSignature: groupSignatureByID[groupID],
                    selectedOverlayID: state.selectedOverlayID,
                    vectorization: state.vectorization,
                    nativeTextOverrides: Dictionary(
                        uniqueKeysWithValues: state.nativeTextOverrides.map { key, value in
                            (key.rawValue, value)
                        }
                    ),
                    nativeContentOverrides: Dictionary(
                        uniqueKeysWithValues: state.nativeContentOverrides.map { key, value in
                            (key.rawValue, value)
                        }
                    ),
                    nativeLayoutOverrides: Dictionary(
                        uniqueKeysWithValues: state.nativeLayoutOverrides.map { key, value in
                            (key.rawValue, value)
                        }
                    ),
                    overlays: state.overlays.map(presentationOverlayRecord(from:))
                )
            )
        }

        let decoder = JSONDecoder()
        let decodedExistingCandidates = presentationStateDecodeCandidates(for: file).compactMap { candidate -> (source: String, data: Data, payload: PresentationPersistedState)? in
            guard let payload = try? decoder.decode(PresentationPersistedState.self, from: candidate.data) else {
                return nil
            }
            return (candidate.source, candidate.data, payload)
        }
        let existingPersisted = preferredPresentationPersistedCandidate(decodedExistingCandidates)?.payload

        let hasInMemoryStyling = !(stateByGroup.isEmpty)
        let hasTouchedStyling = presentationStylingTouchedFileIDs.contains(fileID)
        if orderedPersistedGroups.isEmpty,
           !hasInMemoryStyling,
           !hasTouchedStyling,
           let existingPersisted,
           !existingPersisted.groups.isEmpty {
            orderedPersistedGroups = existingPersisted.groups
        }

        let selectedGroupID = selectedPresentationGroupIDByFile[fileID] ?? existingPersisted?.selectedGroupID
        let selectedGroupSignature = selectedGroupID.flatMap { groupSignatureByID[$0] } ?? existingPersisted?.selectedGroupSignature
        let resolvedBreaks: [Int] = {
            if let breaks = presentationBreaksByFile[fileID] {
                return Array(breaks).sorted()
            }
            return existingPersisted?.breaks ?? []
        }()
        let resolvedExcludedIDs: [UUID] = {
            if let excluded = presentationExcludedNodeIDsByFile[fileID] {
                return Array(excluded).sorted { $0.uuidString < $1.uuidString }
            }
            return (existingPersisted?.excludedNodeIDs ?? []).sorted { $0.uuidString < $1.uuidString }
        }()
        let persisted = PresentationPersistedState(
            breaks: resolvedBreaks,
            excludedNodeIDs: resolvedExcludedIDs,
            selectedGroupID: selectedGroupID,
            selectedGroupSignature: selectedGroupSignature,
            pageStyle: presentationPageStyleByFile[fileID] ?? existingPersisted?.pageStyle ?? .default,
            textTheme: presentationTextThemeByFile[fileID] ?? existingPersisted?.textTheme ?? .default,
            updatedAt: .now,
            groups: orderedPersistedGroups
        )

        let encoder = JSONEncoder()
        let data: Data
        do {
            data = try encoder.encode(persisted)
        } catch {
            persistenceLog("❌ Failed to encode presentation state for file \(fileID): \(error)", force: true)
            return
        }

        let sidecarWriteSucceeded = writePresentationStateToSidecar(fileID: fileID, data: data)
        let inlinePayload = sidecarWriteSucceeded
            ? presentationStateInlineMarkerData(fileID: fileID)
            : data
        let shouldSaveModel = file.presentationStateData != inlinePayload

        if shouldSaveModel {
            file.presentationStateData = inlinePayload
            file.updatedAt = .now
            do {
                try modelContext.save()
            } catch {
                persistenceLog("❌ Failed to persist presentation state: \(error)", force: true)
            }
        }

        if presentationPersistenceDebugEnabled {
            let overlayCount = persisted.groups.reduce(0) { partialResult, group in
                partialResult + group.overlays.count
            }
            persistenceLog(
                "💾 Persisted presentation state file=\(fileID) groups=\(persisted.groups.count) " +
                "overlays=\(overlayCount) bytes=\(data.count) sidecar=\(sidecarWriteSucceeded) " +
                "inlineBytes=\(inlinePayload.count) touched=\(hasTouchedStyling)"
            )
        }
    }

    private func presentationOverlayRecord(from overlay: PresentationSlideOverlay) -> PresentationPersistedOverlay {
        let persistedImageData = normalizedPersistentImageData(overlay.imageData)
        let persistedExtractedData = overlay.extractedImageData.map { normalizedPersistentImageData($0) }
        let persistedCropSourceData = overlay.cropSourceImageData.map { normalizedPersistentImageData($0) }
        let normalizedCrop = normalizedUnitCropRect(overlay.cumulativeCropRect)
        return PresentationPersistedOverlay(
            id: overlay.id,
            kindRaw: overlay.kind.rawValue,
            imageData: persistedImageData,
            extractedImageData: persistedExtractedData,
            cropSourceImageData: persistedCropSourceData,
            cropOriginX: clampedFiniteDouble(Double(normalizedCrop.origin.x), range: 0...1, fallback: 0),
            cropOriginY: clampedFiniteDouble(Double(normalizedCrop.origin.y), range: 0...1, fallback: 0),
            cropWidth: clampedFiniteDouble(Double(normalizedCrop.width), range: 0.02...1, fallback: 1),
            cropHeight: clampedFiniteDouble(Double(normalizedCrop.height), range: 0.02...1, fallback: 1),
            vectorDocument: overlay.vectorDocument.map {
                PresentationPersistedSVGDocument(
                    width: $0.width,
                    height: $0.height,
                    body: $0.body
                )
            },
            selectedFilterRaw: overlay.selectedFilter.rawValue,
            stylization: PresentationPersistedStylization(from: overlay.stylization),
            centerX: clampedFiniteDouble(Double(overlay.center.x), range: 0...1, fallback: 0.5),
            centerY: clampedFiniteDouble(Double(overlay.center.y), range: 0...1, fallback: 0.58),
            normalizedWidth: clampedFiniteDouble(Double(overlay.normalizedWidth), range: 0.08...0.96, fallback: 0.28),
            normalizedHeight: clampedFiniteDouble(Double(overlay.normalizedHeight), range: 0.08...0.96, fallback: 0.2),
            aspectRatio: clampedFiniteDouble(Double(overlay.aspectRatio), range: 0.15...10, fallback: 1),
            rotationDegrees: finiteDouble(overlay.rotationDegrees, fallback: 0),
            textContent: overlay.textContent,
            textStylePreset: overlay.textStylePreset,
            textColorHex: overlay.textColorHex,
            textAlignment: overlay.textAlignment,
            textFontSize: clampedFiniteDouble(overlay.textFontSize, range: 8...180, fallback: 24),
            textWeightValue: clampedFiniteDouble(overlay.textWeightValue, range: 0...1, fallback: 0.5),
            shapeFillColorHex: overlay.shapeFillColorHex,
            shapeBorderColorHex: overlay.shapeBorderColorHex,
            shapeBorderWidth: clampedFiniteDouble(overlay.shapeBorderWidth, range: 0...24, fallback: 1.2),
            shapeCornerRadiusRatio: clampedFiniteDouble(overlay.shapeCornerRadiusRatio, range: 0...0.5, fallback: 0.18),
            shapeStyleRaw: overlay.shapeStyle.rawValue,
            iconSystemName: overlay.iconSystemName,
            iconColorHex: overlay.iconColorHex,
            iconHasBackground: overlay.iconHasBackground,
            iconBackgroundColorHex: overlay.iconBackgroundColorHex,
            imageCornerRadiusRatio: clampedFiniteDouble(overlay.imageCornerRadiusRatio, range: 0...0.5, fallback: 0),
            vectorStrokeColorHex: overlay.vectorStrokeColorHex,
            vectorBackgroundColorHex: overlay.vectorBackgroundColorHex,
            vectorBackgroundVisible: overlay.vectorBackgroundVisible
        )
    }

    private func remappedPresentationGroupStates(
        fileID: UUID,
        graphData: Data,
        persistedGroups: [PresentationPersistedGroupState],
        pageStyle: PresentationPageStyle,
        textTheme: PresentationTextTheme
    ) -> [UUID: PresentationSlideStylingState] {
        guard !persistedGroups.isEmpty else { return [:] }

        let rawDeck = EduPresentationPlanner.makeDeck(graphData: graphData)
        let filteredDeck = filteredPresentationDeck(for: fileID, from: rawDeck)
        let currentGroups = presentationGroups(for: fileID, deck: filteredDeck)
        guard !currentGroups.isEmpty else {
            var fallback: [UUID: PresentationSlideStylingState] = [:]
            for group in persistedGroups {
                fallback[group.groupID] = hydratedPresentationGroupState(
                    group,
                    pageStyle: pageStyle,
                    textTheme: textTheme
                )
            }
            return fallback
        }

        let currentIDs = Set(currentGroups.map(\.id))
        let currentSignatureToID = Dictionary(
            uniqueKeysWithValues: currentGroups.map { group in
                (presentationGroupSignature(group), group.id)
            }
        )

        var remapped: [UUID: PresentationSlideStylingState] = [:]
        var usedPersistedIndices = Set<Int>()

        // 1) Exact group ID match.
        for (index, persistedGroup) in persistedGroups.enumerated() {
            guard currentIDs.contains(persistedGroup.groupID) else { continue }
            remapped[persistedGroup.groupID] = hydratedPresentationGroupState(
                persistedGroup,
                pageStyle: pageStyle,
                textTheme: textTheme
            )
            usedPersistedIndices.insert(index)
        }

        // 2) Signature match.
        for (index, persistedGroup) in persistedGroups.enumerated() where !usedPersistedIndices.contains(index) {
            guard let signature = persistedGroup.groupSignature,
                  let matchedID = currentSignatureToID[signature],
                  remapped[matchedID] == nil else {
                continue
            }
            remapped[matchedID] = hydratedPresentationGroupState(
                persistedGroup,
                pageStyle: pageStyle,
                textTheme: textTheme
            )
            usedPersistedIndices.insert(index)
        }

        // 3) Index fallback for remaining groups.
        let unmatchedCurrentIDsInOrder = currentGroups.map(\.id).filter { remapped[$0] == nil }
        let remainingPersistedIndices = persistedGroups.indices.filter { !usedPersistedIndices.contains($0) }
        for (targetID, persistedIndex) in zip(unmatchedCurrentIDsInOrder, remainingPersistedIndices) {
            remapped[targetID] = hydratedPresentationGroupState(
                persistedGroups[persistedIndex],
                pageStyle: pageStyle,
                textTheme: textTheme
            )
        }

        return remapped
    }

    private func hydratedPresentationGroupState(
        _ group: PresentationPersistedGroupState,
        pageStyle: PresentationPageStyle,
        textTheme: PresentationTextTheme
    ) -> PresentationSlideStylingState {
        var state = PresentationSlideStylingState.empty
        state.selectedOverlayID = group.selectedOverlayID
        state.vectorization = group.vectorization
        state.pageStyle = pageStyle
        state.textTheme = textTheme
        state.nativeTextOverrides = group.nativeTextOverrides.reduce(into: [:]) { partial, entry in
            guard let element = PresentationNativeElement(rawValue: entry.key) else { return }
            partial[element] = entry.value
        }
        state.nativeContentOverrides = group.nativeContentOverrides.reduce(into: [:]) { partial, entry in
            guard let element = PresentationNativeElement(rawValue: entry.key) else { return }
            partial[element] = entry.value
        }
        state.nativeLayoutOverrides = group.nativeLayoutOverrides.reduce(into: [:]) { partial, entry in
            guard let element = PresentationNativeElement(rawValue: entry.key) else { return }
            partial[element] = entry.value
        }
        state.overlays = group.overlays.map { overlay in
            presentationOverlay(from: overlay)
        }
        return state
    }

    private func presentationGroupSignature(_ group: EduPresentationSlideGroup) -> String {
        group.sourceSlides.map { $0.id.uuidString }.joined(separator: "|")
    }

    private func finiteDouble(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? value : fallback
    }

    private func clampedFiniteDouble(_ value: Double, range: ClosedRange<Double>, fallback: Double) -> Double {
        let finite = finiteDouble(value, fallback: fallback)
        return min(range.upperBound, max(range.lowerBound, finite))
    }

    private func normalizedPersistentImageData(_ data: Data) -> Data {
        let maxPersistedBytes = 900_000
        guard data.count > maxPersistedBytes else { return data }
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return data }
        let width = max(1, image.size.width)
        let height = max(1, image.size.height)
        let maxEdge = max(width, height)
        let targetMaxEdge: CGFloat = 1280
        let scale = min(1, targetMaxEdge / maxEdge)
        let targetSize = CGSize(
            width: max(1, floor(width * scale)),
            height: max(1, floor(height * scale))
        )

        let hasAlpha = imageHasAlpha(image)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = !hasAlpha
        let rendered = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        if hasAlpha {
            if let png = rendered.pngData(), png.count < data.count {
                return png
            }
            return data
        }

        if let jpeg = rendered.jpegData(compressionQuality: 0.72), jpeg.count < data.count {
            return jpeg
        }
        return data
        #else
        return data
        #endif
    }

    #if canImport(UIKit)
    private func imageHasAlpha(_ image: UIImage) -> Bool {
        guard let alphaInfo = image.cgImage?.alphaInfo else { return false }
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        default:
            return false
        }
    }
    #endif

    private func presentationStateDecodeCandidates(for file: GNodeWorkspaceFile) -> [(source: String, data: Data)] {
        var candidates: [(source: String, data: Data)] = []

        if let sidecarData = loadPresentationStateFromSidecar(fileID: file.id), !sidecarData.isEmpty {
            candidates.append((source: "sidecar", data: sidecarData))
        }

        let inlineData = resolvedInlinePresentationStateData(file.presentationStateData)
        if !inlineData.isEmpty {
            candidates.append((source: "inline", data: inlineData))
        }

        return candidates
    }

    private func resolvedInlinePresentationStateData(_ raw: Data) -> Data {
        guard !raw.isEmpty else { return Data() }
        guard let marker = String(data: raw, encoding: .utf8),
              marker.hasPrefix(presentationStateMarkerPrefix) else {
            return raw
        }
        return Data()
    }

    private var presentationStateMarkerPrefix: String {
        "edunode.presentation.sidecar:"
    }

    private func presentationStateInlineMarkerData(fileID: UUID) -> Data {
        Data("\(presentationStateMarkerPrefix)\(fileID.uuidString)".utf8)
    }

    private func preferredPresentationPersistedCandidate(
        _ candidates: [(source: String, data: Data, payload: PresentationPersistedState)]
    ) -> (source: String, data: Data, payload: PresentationPersistedState)? {
        candidates.max(by: { lhs, rhs in
            presentationPersistedCandidateSortsAscending(lhs: lhs, rhs: rhs)
        })
    }

    private func presentationPersistedCandidateSortsAscending(
        lhs: (source: String, data: Data, payload: PresentationPersistedState),
        rhs: (source: String, data: Data, payload: PresentationPersistedState)
    ) -> Bool {
        let lhsHasGroups = !lhs.payload.groups.isEmpty
        let rhsHasGroups = !rhs.payload.groups.isEmpty
        if lhsHasGroups != rhsHasGroups {
            return !lhsHasGroups && rhsHasGroups
        }

        let lhsIsSidecar = lhs.source == "sidecar"
        let rhsIsSidecar = rhs.source == "sidecar"
        if lhsIsSidecar != rhsIsSidecar {
            return !lhsIsSidecar && rhsIsSidecar
        }

        let lhsDate = lhs.payload.updatedAt ?? .distantPast
        let rhsDate = rhs.payload.updatedAt ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate < rhsDate
        }

        if lhs.payload.groups.count != rhs.payload.groups.count {
            return lhs.payload.groups.count < rhs.payload.groups.count
        }

        return lhs.data.count < rhs.data.count
    }

    private func presentationStateDirectoryURL() -> URL? {
        let fileManager = FileManager.default
        let roots: [URL] = [
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        ]
        .compactMap { $0 }

        for root in roots {
            let directory = root.appendingPathComponent("PresentationState", isDirectory: true)
            if !fileManager.fileExists(atPath: directory.path) {
                do {
                    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                } catch {
                    if presentationPersistenceDebugEnabled {
                        persistenceLog("⚠️ Failed to create PresentationState directory at \(directory.path): \(error)", force: true)
                    }
                    continue
                }
            }
            return directory
        }

        if presentationPersistenceDebugEnabled {
            persistenceLog("❌ Unable to resolve PresentationState directory.", force: true)
        }
        return nil
    }

    private func presentationStateSidecarURL(fileID: UUID) -> URL? {
        guard let directory = presentationStateDirectoryURL() else {
            if presentationPersistenceDebugEnabled {
                persistenceLog("❌ No PresentationState directory available for file \(fileID).", force: true)
            }
            return nil
        }
        return directory.appendingPathComponent("\(fileID.uuidString).json")
    }

    private func loadPresentationStateFromSidecar(fileID: UUID) -> Data? {
        guard let url = presentationStateSidecarURL(fileID: fileID) else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            if presentationPersistenceDebugEnabled {
                persistenceLog("⚠️ Failed to read presentation sidecar for file \(fileID) at \(url.path): \(error)", force: true)
            }
            return nil
        }
    }

    @discardableResult
    private func writePresentationStateToSidecar(fileID: UUID, data: Data) -> Bool {
        guard let url = presentationStateSidecarURL(fileID: fileID) else {
            persistenceLog("❌ Failed to write presentation sidecar for file \(fileID): no valid sidecar URL", force: true)
            return false
        }
        do {
            try data.write(to: url, options: .atomic)
            if presentationPersistenceDebugEnabled {
                persistenceLog("🗂️ Wrote presentation sidecar file=\(fileID) bytes=\(data.count) path=\(url.path)")
            }
            return true
        } catch {
            persistenceLog("❌ Failed to write presentation sidecar for file \(fileID) at \(url.path): \(error)", force: true)
            return false
        }
    }

    private func removePresentationStateSidecar(fileID: UUID) {
        guard let url = presentationStateSidecarURL(fileID: fileID) else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            persistenceLog("⚠️ Failed to remove presentation sidecar for file \(fileID): \(error)", force: true)
        }
    }

    private func persistenceLog(_ message: String, force: Bool = false) {
        guard force || presentationPersistenceDebugEnabled else { return }
        let tagged = "EDUNODE_PERSIST | \(message)"
        lastPersistLog = tagged
        print(tagged)
        NSLog("%@", tagged)
        appendDiagnosticLogLine(tagged)
    }

    private func appendDiagnosticLogLine(_ line: String) {
        let fileManager = FileManager.default
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let url = documents.appendingPathComponent("edunode_debug.log")
        guard let data = (line + "\n").data(using: .utf8) else { return }

        if fileManager.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
                return
            } catch {
                try? handle.close()
            }
        }

        try? data.write(to: url, options: .atomic)
    }

    private func presentationOverlay(from record: PresentationPersistedOverlay) -> PresentationSlideOverlay {
        let kind = PresentationOverlayKind(rawValue: record.kindRaw) ?? .image
        let selectedFilter = SVGFilterStyle(rawValue: record.selectedFilterRaw) ?? .original
        return PresentationSlideOverlay(
            id: record.id,
            kind: kind,
            imageData: record.imageData,
            extractedImageData: record.extractedImageData,
            cropSourceImageData: record.cropSourceImageData,
            cumulativeCropRect: CGRect(
                x: record.cropOriginX,
                y: record.cropOriginY,
                width: record.cropWidth,
                height: record.cropHeight
            ),
            vectorDocument: record.vectorDocument.map {
                SVGDocument(width: $0.width, height: $0.height, body: $0.body)
            },
            selectedFilter: selectedFilter,
            stylization: record.stylization.value,
            center: CGPoint(x: record.centerX, y: record.centerY),
            normalizedWidth: CGFloat(record.normalizedWidth),
            normalizedHeight: CGFloat(record.normalizedHeight),
            aspectRatio: CGFloat(record.aspectRatio),
            rotationDegrees: record.rotationDegrees,
            isExtracting: false,
            activeVectorizationRequestID: nil,
            textContent: record.textContent,
            textStylePreset: record.textStylePreset,
            textColorHex: record.textColorHex,
            textAlignment: record.textAlignment,
            textFontSize: record.textFontSize,
            textWeightValue: record.textWeightValue,
            shapeFillColorHex: record.shapeFillColorHex,
            shapeBorderColorHex: record.shapeBorderColorHex,
            shapeBorderWidth: record.shapeBorderWidth,
            shapeCornerRadiusRatio: record.shapeCornerRadiusRatio,
            shapeStyle: PresentationShapeStyle(rawValue: record.shapeStyleRaw) ?? .roundedRect,
            iconSystemName: record.iconSystemName,
            iconColorHex: record.iconColorHex,
            iconHasBackground: record.iconHasBackground,
            iconBackgroundColorHex: record.iconBackgroundColorHex,
            imageCornerRadiusRatio: record.imageCornerRadiusRatio,
            vectorStrokeColorHex: record.vectorStrokeColorHex,
            vectorBackgroundColorHex: record.vectorBackgroundColorHex,
            vectorBackgroundVisible: record.vectorBackgroundVisible
        )
    }

    private func deleteWorkspaceFile(_ file: GNodeWorkspaceFile) {
        let currentID = file.id
        let orderedIDs = workspaceFiles.map(\.id)
        let currentIndex = orderedIDs.firstIndex(of: currentID) ?? 0
        let remainingIDs = orderedIDs.filter { $0 != currentID }

        modelContext.delete(file)
        try? modelContext.save()
        removePresentationStateSidecar(fileID: currentID)

        if remainingIDs.isEmpty {
            selectedFileID = nil
            return
        }

        if selectedFileID == currentID {
            let nextIndex = min(currentIndex, remainingIDs.count - 1)
            selectedFileID = remainingIDs[nextIndex]
        }
    }

    private func persistWorkspaceFileData(id: UUID, data: Data) {
        guard let file = workspaceFiles.first(where: { $0.id == id }) else { return }
        guard file.data != data else { return }

        file.data = data
        file.updatedAt = .now
        try? modelContext.save()
    }

    private func importWorkspaceFile(data: Data, suggestedName: String) {
        let trimmed = suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = String(format: S("app.files.defaultName"), workspaceFiles.count + 1)
        let name = trimmed.isEmpty ? fallback : trimmed
        let migratedData = EduPlanning.migrateLegacyKnowledgeInputsAndSampleConnectionsIfNeeded(data: data) ?? data

        let file = GNodeWorkspaceFile(
            name: name,
            data: migratedData,
            knowledgeToolkitMarkedDone: EduPlanning.isZhuhaiSampleData(migratedData)
        )
        modelContext.insert(file)
        try? modelContext.save()
        selectedFileID = file.id
    }

    private func flowStates(for file: GNodeWorkspaceFile) -> [EduFlowStepState] {
        let basicInfoDone = isBasicInfoComplete(file)
        let modelDone = !file.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let knowledgeToolkitDone = file.knowledgeToolkitMarkedDone
        let evaluationDesignDone = EduPlanning.hasEvaluationDesign(in: file.data)

        let canMarkKnowledgeToolkit = true
        let canMarkLesson = knowledgeToolkitDone && evaluationDesignDone
        let canMarkEvaluation = file.lessonPlanMarkedDone && evaluationDesignDone
        let lessonDone = file.lessonPlanMarkedDone && canMarkLesson
        let evaluationDone = file.evaluationMarkedDone && canMarkEvaluation

        return [
            EduFlowStepState(step: .basicInfo, index: 1, isDone: basicInfoDone, isManual: false, canToggle: false),
            EduFlowStepState(step: .modelSelection, index: 2, isDone: modelDone, isManual: false, canToggle: false),
            EduFlowStepState(step: .knowledgeToolkit, index: 3, isDone: knowledgeToolkitDone, isManual: true, canToggle: canMarkKnowledgeToolkit),
            EduFlowStepState(step: .evaluationDesign, index: 4, isDone: evaluationDesignDone, isManual: false, canToggle: false),
            EduFlowStepState(step: .lessonPlan, index: 5, isDone: lessonDone, isManual: true, canToggle: canMarkLesson),
            EduFlowStepState(step: .evaluationSummary, index: 6, isDone: evaluationDone, isManual: true, canToggle: canMarkEvaluation)
        ]
    }

    private func toggleManualStep(_ step: EduFlowStep, for file: GNodeWorkspaceFile) {
        let knowledgeToolkitDone = file.knowledgeToolkitMarkedDone
        let evaluationDesignDone = EduPlanning.hasEvaluationDesign(in: file.data)

        switch step {
        case .knowledgeToolkit:
            file.knowledgeToolkitMarkedDone.toggle()
            if !file.knowledgeToolkitMarkedDone {
                file.lessonPlanMarkedDone = false
                file.evaluationMarkedDone = false
            }

        case .lessonPlan:
            guard knowledgeToolkitDone && evaluationDesignDone else { return }
            file.lessonPlanMarkedDone.toggle()
            if !file.lessonPlanMarkedDone {
                file.evaluationMarkedDone = false
            }

        case .evaluationSummary:
            guard file.lessonPlanMarkedDone && knowledgeToolkitDone && evaluationDesignDone else { return }
            file.evaluationMarkedDone.toggle()

        case .basicInfo, .modelSelection, .evaluationDesign:
            return
        }

        file.updatedAt = .now
        try? modelContext.save()
    }

    private func isBasicInfoComplete(_ file: GNodeWorkspaceFile) -> Bool {
        !file.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        file.gradeMin > 0 &&
        file.gradeMax >= file.gradeMin &&
        !file.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        file.lessonDurationMinutes > 0 &&
        file.studentCount > 0 &&
        !file.goalsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func handleFlowStepTap(_ step: EduFlowStep, for file: GNodeWorkspaceFile) {
        guard let state = flowStates(for: file).first(where: { $0.step == step }),
              state.canToggle else {
            return
        }

        if step == .knowledgeToolkit {
            pendingFlowStepConfirmation = step
            pendingFlowStepFileID = file.id
            pendingFlowStepIsDone = state.isDone
            return
        }

        toggleManualStep(step, for: file)
    }

    private func confirmPendingFlowStep() {
        guard let step = pendingFlowStepConfirmation,
              let fileID = pendingFlowStepFileID,
              let file = workspaceFiles.first(where: { $0.id == fileID }) else {
            clearPendingFlowStepConfirmation()
            return
        }

        toggleManualStep(step, for: file)
        clearPendingFlowStepConfirmation()
    }

    private func clearPendingFlowStepConfirmation() {
        pendingFlowStepConfirmation = nil
        pendingFlowStepFileID = nil
        pendingFlowStepIsDone = false
    }

    @ViewBuilder
    private func sidebarFileRow(_ file: GNodeWorkspaceFile) -> some View {
        let isSelected = selectedFileID == file.id

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "doc.text.fill" : "doc.text")
                    .foregroundStyle(isSelected ? .cyan : .secondary)
                    .font(.body.weight(.semibold))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name)
                        .font(isSelected ? .body.weight(.semibold) : .body)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isSelected {
                sidebarCourseContextCard(file: file)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, isSelected ? 4 : 2)
    }

    private func fileSubtitle(_ file: GNodeWorkspaceFile) -> String {
        let subjectPart = file.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let gradePrefix = file.gradeMode == "age" ? S("course.gradeMode.age") : S("course.gradeMode.grade")
        let gradePart = "\(gradePrefix) \(file.gradeMin)-\(file.gradeMax)"

        if !subjectPart.isEmpty || !gradePart.isEmpty {
            let info = [subjectPart, gradePart].filter { !$0.isEmpty }.joined(separator: " · ")
            return info
        }

        return file.updatedAt.formatted(.dateTime.month().day().hour().minute())
    }

    private func gradeSummary(for file: GNodeWorkspaceFile) -> String {
        let mode = file.gradeMode == "age" ? S("course.gradeMode.age") : S("course.gradeMode.grade")
        return "\(mode) \(file.gradeMin)-\(file.gradeMax)"
    }

    private func modelSummary(for file: GNodeWorkspaceFile) -> String {
        let isChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        if let rule = modelRules.first(where: { $0.id == file.modelID }) {
            return rule.displayName(isChinese: isChinese)
        }
        return file.modelID
    }

    private func goalItems(for file: GNodeWorkspaceFile) -> [String] {
        file.goalsText
            .split(whereSeparator: { $0 == "\n" || $0 == ";" || $0 == "；" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func zhuhaiSampleGoals(isChinese: Bool) -> String {
        if isChinese {
            return """
能够识别并准确读出 7 种那洲常见鸟名，完成留鸟/候鸟分类与举例说明。
能够解释“那洲气候与地形如何影响鸟类分布”，把地理信息与鸟种特征联系起来。
能够依据鸟种需求选择合适巢型（碗状/盘状/悬挂），并说出至少 1 条设计依据。
能够在双人协作中完成“结构选择-材料填充-创意装饰”三步搭建，并记录关键决策过程。
能够在展览环节完成成果讲解，清晰表达鸟巢命名、悬挂位置、设计亮点与主要挑战。
能够在课后 1 个月借助拍图识鸟工具持续观察，至少提交 1 次真实场景记录并分享发现。
"""
        }

        return """
Identify and correctly pronounce 7 common Nazhou birds, then classify resident vs migratory birds with examples.
Explain how Nazhou's climate and terrain shape bird distribution, linking geography to species traits.
Select a suitable nest type (bowl/plate/hanging) for each bird and justify the choice with at least one design reason.
Complete pair-based nest building through structure selection, material filling, and creative decoration while recording key decisions.
Present the final nest with clear rationale, including nest name, intended placement, highlights, and major challenges.
Continue one-month post-class bird observation with photo identification and share at least one real-world record.
"""
    }

    private func zhuhaiLegacyGoals(isChinese: Bool) -> String {
        if isChinese {
            return """
识别7种珠海常见鸟并区分留鸟与候鸟
理解鸟种特征与巢型匹配关系
完成两人协作鸟巢设计、搭建与展示表达
通过课后拍图识鸟延伸观察与生态兴趣
"""
        }

        return """
Identify 7 common Zhuhai birds and classify resident vs migratory types
Explain bird traits and nest-type matching logic
Complete pair-based nest design, building, and showcase expression
Extend learning with monthly photo bird identification
"""
    }

    private func normalizedMultiline(_ value: String) -> String {
        value
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func inferredChinesePreference(for file: GNodeWorkspaceFile) -> Bool {
        let candidate = "\(file.name)\n\(file.subject)\n\(file.goalsText)"
        if candidate.range(of: #"[一-龥]"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private func shouldUpgradeZhuhaiGoals(for file: GNodeWorkspaceFile) -> Bool {
        let current = normalizedMultiline(file.goalsText)
        if current.isEmpty { return true }
        let oldChinese = normalizedMultiline(zhuhaiLegacyGoals(isChinese: true))
        let oldEnglish = normalizedMultiline(zhuhaiLegacyGoals(isChinese: false))
        return current == oldChinese || current == oldEnglish
    }

    private func effectiveGoals(for file: GNodeWorkspaceFile) -> [String] {
        let goals = goalItems(for: file)
        if !goals.isEmpty { return goals }
        if EduPlanning.isZhuhaiSampleData(file.data) {
            return zhuhaiSampleGoals(isChinese: inferredChinesePreference(for: file))
                .split(whereSeparator: \.isNewline)
                .map { String($0) }
        }
        return []
    }

    private func isChineseUI() -> Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    @ViewBuilder
    private func sidebarCourseContextCard(file: GNodeWorkspaceFile) -> some View {
        let goals = effectiveGoals(for: file)
        let visibleGoals = Array(goals.prefix(8))
        let model = modelSummary(for: file)
        let subject = file.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let periodRange = file.periodRange.trimmingCharacters(in: .whitespacesAndNewlines)
        let team = file.teacherTeam.trimmingCharacters(in: .whitespacesAndNewlines)
        let grouping = file.studentProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        let subjectDisplay = subject.isEmpty ? S("app.context.none") : subject
        let periodDisplay = periodRange.isEmpty ? S("app.context.none") : periodRange
        let teamDisplay = team.isEmpty ? S("app.context.none") : team
        let groupingDisplay = grouping.isEmpty ? S("app.context.none") : grouping

        VStack(alignment: .leading, spacing: 8) {
            Button {
                // Keep row header/icon visually stable by avoiding List row geometry animation here.
                isSidebarBasicInfoExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text(S("flow.basicInfo"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Image(systemName: isSidebarBasicInfoExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSidebarBasicInfoExpanded {
                VStack(alignment: .leading, spacing: 7) {
                    sidebarContextRow(label: S("course.subject"), value: subjectDisplay)
                    sidebarContextRow(label: S("course.gradeMode"), value: gradeSummary(for: file))
                    sidebarContextRow(label: S("course.studentCount"), value: "\(file.studentCount)")
                    sidebarContextRow(label: S("course.duration"), value: "\(file.lessonDurationMinutes)m")
                    sidebarContextRow(label: S("app.context.model"), value: model)
                    sidebarContextRow(label: S("course.teacherTeam"), value: teamDisplay)
                    sidebarContextRow(label: S("course.section.students"), value: groupingDisplay)
                    sidebarContextRow(label: S("course.periodRange"), value: periodDisplay)
                }
                .padding(.top, 2)
            }

            Divider()
                .overlay(Color.white.opacity(0.14))

            Text(S("app.context.goals"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)

            if visibleGoals.isEmpty {
                Text(S("app.context.none"))
                    .font(.caption2)
                    .foregroundStyle(.white)
            } else {
                ForEach(Array(visibleGoals.enumerated()), id: \.offset) { index, goal in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(index + 1).")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(goal)
                            .font(.caption2)
                            .lineLimit(3)
                            .foregroundStyle(.white)
                    }
                }
            }

            if goals.count > visibleGoals.count {
                Text("+\(goals.count - visibleGoals.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func editorStatsOverlay(stats: NodeEditorCanvasStats) -> some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                Text("Node: \(stats.nodeCount) | Zoom: \(stats.zoomPercent)%")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            }
            .padding(.trailing, 20)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .allowsHitTesting(false)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    @ViewBuilder
    private var presentationPreparingOverlay: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: 0) {
                ZStack {
                    Color.clear
                        .ignoresSafeArea()

                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(Color.black.opacity(0.26))
                        .ignoresSafeArea()
                    .allowsHitTesting(false)

                    VStack(spacing: 10) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.primary)
                        Text(isChineseUI() ? "正在准备演讲模式…" : "Preparing presentation mode…")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .glassEffect(
                        .regular,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                }
            }
            .allowsHitTesting(true)
        } else {
            ZStack {
                Color.black.opacity(0.76)
                    .ignoresSafeArea()
                Rectangle()
                    .fill(.ultraThickMaterial)
                    .opacity(0.72)
                    .ignoresSafeArea()
                Rectangle()
                    .fill(Color.black.opacity(0.18))
                    .ignoresSafeArea()

                VStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                    Text(isChineseUI() ? "正在准备演讲模式…" : "Preparing presentation mode…")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            }
            .allowsHitTesting(true)
        }
    }

    @ViewBuilder
    private func sidebarContextRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.caption2.weight(.semibold))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func editorToolbarActions(for file: GNodeWorkspaceFile) -> [NodeEditorToolbarAction] {
        let isActive = activePresentationModeFileID == file.id || presentationModeLoadingFileID == file.id
        return [
            NodeEditorToolbarAction(
                id: "edunode.present",
                title: S("app.presentation.button"),
                systemImage: "play.rectangle.on.rectangle",
                accent: .orange,
                isActive: isActive,
                minWidth: 108
            ) {
                togglePresentationMode(for: file)
            }
        ]
    }

    private func editorConnectionAppearance(
        for _: NodeConnection,
        sourceNodeType: String?,
        targetNodeType: String?
    ) -> NodeEditorConnectionAppearance? {
        let involvesEvaluation = sourceNodeType == EduNodeType.evaluation || targetNodeType == EduNodeType.evaluation
        guard involvesEvaluation else { return nil }
        return NodeEditorConnectionAppearance(
            color: Color.gray.opacity(0.78),
            lineWidth: 2.5,
            dash: [10, 7]
        )
    }

    private func togglePresentationMode(for file: GNodeWorkspaceFile) {
        if presentationModeLoadingFileID == file.id {
            presentationModeActivationToken = nil
            presentationModeLoadingFileID = nil
            pendingPresentationThumbnailIDsByFile[file.id] = nil
            return
        }

        if activePresentationModeFileID == file.id {
            activePresentationModeFileID = nil
            if activePresentationStylingFileID == file.id {
                activePresentationStylingFileID = nil
            }
            presentationModeActivationToken = nil
            presentationModeLoadingFileID = nil
            pendingPresentationThumbnailIDsByFile[file.id] = nil
            return
        }

        activePresentationStylingFileID = nil
        let activationToken = UUID()
        presentationModeActivationToken = activationToken
        presentationModeLoadingFileID = file.id

        Task { @MainActor in
            await Task.yield()
            guard presentationModeActivationToken == activationToken else { return }

            // Force a fresh restore each time user enters Present mode to avoid stale in-memory state.
            hydratePresentationState(for: file, force: true)

            let rawDeck = EduPresentationPlanner.makeDeck(graphData: file.data)
            let deck = filteredPresentationDeck(for: file.id, from: rawDeck)
            guard !deck.orderedSlides.isEmpty else {
                if presentationModeActivationToken == activationToken {
                    presentationModeLoadingFileID = nil
                    pendingPresentationThumbnailIDsByFile[file.id] = nil
                    showingPresentationEmptyAlert = true
                }
                return
            }
            let groups = presentationGroups(for: file.id, deck: deck)
            guard !groups.isEmpty else {
                if presentationModeActivationToken == activationToken {
                    presentationModeLoadingFileID = nil
                    pendingPresentationThumbnailIDsByFile[file.id] = nil
                    showingPresentationEmptyAlert = true
                }
                return
            }

            guard presentationModeActivationToken == activationToken else { return }
            let pendingThumbnailIDs = Set(groups.map(\.id))
            pendingPresentationThumbnailIDsByFile[file.id] = pendingThumbnailIDs
            activePresentationModeFileID = file.id
            splitVisibility = .detailOnly
            if let firstGroup = groups.first {
                selectPresentationGroup(fileID: file.id, group: firstGroup)
            }
            if pendingThumbnailIDs.isEmpty {
                presentationModeLoadingFileID = nil
                pendingPresentationThumbnailIDsByFile[file.id] = nil
            } else {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    guard presentationModeActivationToken == activationToken,
                          presentationModeLoadingFileID == file.id else { return }
                    presentationModeLoadingFileID = nil
                    pendingPresentationThumbnailIDsByFile[file.id] = nil
                }
            }
        }
    }

    private func markPresentationThumbnailLoaded(fileID: UUID, groupID: UUID) {
        guard presentationModeLoadingFileID == fileID else { return }
        guard var pendingIDs = pendingPresentationThumbnailIDsByFile[fileID] else { return }
        guard pendingIDs.contains(groupID) else { return }
        pendingIDs.remove(groupID)
        if pendingIDs.isEmpty {
            pendingPresentationThumbnailIDsByFile[fileID] = nil
            presentationModeLoadingFileID = nil
        } else {
            pendingPresentationThumbnailIDsByFile[fileID] = pendingIDs
        }
    }

    private func openPresentationPreview(for file: GNodeWorkspaceFile, graphData: Data? = nil) {
        let sourceData = graphData ?? file.data
        let rawDeck = EduPresentationPlanner.makeDeck(graphData: sourceData)
        let deck = filteredPresentationDeck(for: file.id, from: rawDeck)
        guard !deck.orderedSlides.isEmpty else {
            showingPresentationEmptyAlert = true
            return
        }
        let groups = presentationGroups(for: file.id, deck: deck)
        let slides = EduPresentationPlanner.composeSlides(
            from: groups,
            isChinese: isChineseUI()
        )
        let overlayHTMLBySlideID = presentationOverlayHTMLBySlideID(fileID: file.id, groups: groups)
        let nativeTextOverridesBySlideID = presentationNativeTextOverridesBySlideID(fileID: file.id, groups: groups)
        let nativeContentOverridesBySlideID = presentationNativeContentOverridesBySlideID(fileID: file.id, groups: groups)
        let nativeLayoutOverridesBySlideID = presentationNativeLayoutOverridesBySlideID(fileID: file.id, groups: groups)
        presentationPreviewPayload = EduPresentationPreviewPayload(
            courseName: file.name,
            baseFileName: sanitizedExportBaseName(file.name),
            slides: slides,
            pageStyle: resolvedPresentationPageStyle(fileID: file.id),
            textTheme: resolvedPresentationTextTheme(fileID: file.id),
            overlayHTMLBySlideID: overlayHTMLBySlideID,
            nativeTextOverridesBySlideID: nativeTextOverridesBySlideID,
            nativeContentOverridesBySlideID: nativeContentOverridesBySlideID,
            nativeLayoutOverridesBySlideID: nativeLayoutOverridesBySlideID
        )
    }

    private func effectivePresentationBreaks(fileID: UUID, slideCount: Int) -> Set<Int> {
        guard slideCount > 1 else { return [] }
        let maxBreak = slideCount - 2
        let stored = presentationBreaksByFile[fileID] ?? EduPresentationPlanner.defaultBreaks(count: slideCount)
        return Set(stored.filter { $0 >= 0 && $0 <= maxBreak })
    }

    private func presentationGroups(for fileID: UUID, deck: EduPresentationDeck) -> [EduPresentationSlideGroup] {
        EduPresentationPlanner.groupSlides(
            deck.orderedSlides,
            breaks: effectivePresentationBreaks(fileID: fileID, slideCount: deck.orderedSlides.count)
        )
    }

    private func filteredPresentationDeck(for fileID: UUID, from rawDeck: EduPresentationDeck) -> EduPresentationDeck {
        let excludedNodeIDs = presentationExcludedNodeIDsByFile[fileID] ?? []
        guard !excludedNodeIDs.isEmpty else { return rawDeck }
        let visibleSlides = rawDeck.orderedSlides.filter { !excludedNodeIDs.contains($0.id) }
        return EduPresentationDeck(orderedSlides: visibleSlides)
    }

    private func presentationOverlayHTMLBySlideID(
        fileID: UUID,
        groups: [EduPresentationSlideGroup]
    ) -> [UUID: String] {
        var result: [UUID: String] = [:]
        let slideAspect = max(0.75, resolvedPresentationPageStyle(fileID: fileID).aspectPreset.ratio)
        let textTheme = resolvedPresentationTextTheme(fileID: fileID)
        for group in groups {
            let overlays = presentationStylingState(fileID: fileID, groupID: group.id).overlays
            let html = presentationOverlayLayerHTML(
                overlays: overlays,
                slideAspect: slideAspect,
                textTheme: textTheme
            )
            if !html.isEmpty {
                result[group.id] = html
            }
        }
        return result
    }

    private func presentationNativeTextOverridesBySlideID(
        fileID: UUID,
        groups: [EduPresentationSlideGroup]
    ) -> [UUID: [PresentationNativeElement: PresentationTextStyleConfig]] {
        groups.reduce(into: [:]) { partial, group in
            let map = presentationStylingState(fileID: fileID, groupID: group.id).nativeTextOverrides
            if !map.isEmpty {
                partial[group.id] = map
            }
        }
    }

    private func presentationNativeContentOverridesBySlideID(
        fileID: UUID,
        groups: [EduPresentationSlideGroup]
    ) -> [UUID: [PresentationNativeElement: String]] {
        groups.reduce(into: [:]) { partial, group in
            let map = presentationStylingState(fileID: fileID, groupID: group.id).nativeContentOverrides
            if !map.isEmpty {
                partial[group.id] = map
            }
        }
    }

    private func presentationNativeLayoutOverridesBySlideID(
        fileID: UUID,
        groups: [EduPresentationSlideGroup]
    ) -> [UUID: [PresentationNativeElement: PresentationNativeLayoutOverride]] {
        groups.reduce(into: [:]) { partial, group in
            let map = presentationStylingState(fileID: fileID, groupID: group.id).nativeLayoutOverrides
            if !map.isEmpty {
                partial[group.id] = map
            }
        }
    }

    private func presentationOverlayLayerHTML(
        overlays: [PresentationSlideOverlay],
        slideAspect: CGFloat,
        textTheme: PresentationTextTheme
    ) -> String {
        overlays.compactMap { overlay in
            presentationOverlayNodeHTML(
                overlay,
                slideAspect: slideAspect,
                textTheme: textTheme
            )
        }.joined(separator: "\n")
    }

    private func presentationOverlayNodeHTML(
        _ overlay: PresentationSlideOverlay,
        slideAspect: CGFloat,
        textTheme: PresentationTextTheme
    ) -> String? {
        _ = slideAspect
        let centerX = max(0.04, min(0.96, overlay.center.x)) * 100
        let centerY = max(0.08, min(0.92, overlay.center.y)) * 100
        let widthPercent = max(2.0, min(96.0, Double(overlay.normalizedWidth * 100)))
        let resolvedNormalizedHeight = overlay.normalizedHeight
        let heightPercent = max(2.0, min(96.0, Double(resolvedNormalizedHeight * 100)))
        let rotationDegrees = cssNumber(overlay.rotationDegrees)

        let basePositionStyle = "left:\(cssNumber(centerX))%;top:\(cssNumber(centerY))%;"
        let rotationTransformStyle = "transform:translate(-50%, -50%) rotate(\(rotationDegrees)deg);"

        if overlay.isText {
            let alignment: String
            switch overlay.textAlignment {
            case .leading:
                alignment = "left"
            case .center:
                alignment = "center"
            case .trailing:
                alignment = "right"
            }
            let themedText = textTheme.style(for: overlay.textStylePreset)
            let fontSizeCqw = max(0.7, min(8.5, themedText.sizeCqw))
            let textWeight = String(themedText.cssWeight)
            let textColor = normalizedOverlayHex(themedText.colorHex, fallback: "#111111")
            let content = escapeOverlayHTML(overlay.textContent)
                .replacingOccurrences(of: "\n", with: "<br/>")
            let style = [
                basePositionStyle,
                "width:\(cssNumber(widthPercent))%;",
                "height:\(cssNumber(heightPercent))%;",
                rotationTransformStyle,
                "color:\(textColor);",
                "font-size:\(cssNumber(fontSizeCqw))cqw;",
                "font-weight:\(textWeight);",
                "text-align:\(alignment);"
            ].joined()
            return "<div class=\"edunode-overlay text\" style=\"\(style)\">\(content)</div>"
        }

        if overlay.isRoundedRect {
            let cornerRatio = cssNumber(max(0.0, min(0.5, overlay.shapeCornerRadiusRatio)))
            let fillColor = normalizedOverlayHex(overlay.shapeFillColorHex, fallback: "#FFFFFF")
            let borderColor = normalizedOverlayHex(overlay.shapeBorderColorHex, fallback: "#D6DDE8")
            let borderWidth = cssNumber(max(0.4, overlay.shapeBorderWidth))
            let borderRadius: String
            switch overlay.shapeStyle {
            case .rectangle:
                borderRadius = "0"
            case .roundedRect:
                borderRadius = "calc(min(\(cssNumber(widthPercent))%, \(cssNumber(heightPercent))%) * \(cornerRatio))"
            case .capsule:
                borderRadius = "9999px"
            case .ellipse:
                borderRadius = "50%"
            }
            let style = [
                basePositionStyle,
                "width:\(cssNumber(widthPercent))%;",
                "height:\(cssNumber(heightPercent))%;",
                rotationTransformStyle,
                "background:\(fillColor);",
                "border:\(borderWidth)px solid \(borderColor);",
                "border-radius:\(borderRadius);"
            ].joined()
            return "<div class=\"edunode-overlay rect\" style=\"\(style)\"></div>"
        }

        if overlay.isIcon {
            let glyph = escapeOverlayHTML(iconFallbackGlyph(systemName: overlay.iconSystemName))
            let iconSizePercent = max(3.0, min(36.0, Double(overlay.normalizedWidth * 100)))
            let background = overlay.iconHasBackground
                ? normalizedOverlayHex(overlay.iconBackgroundColorHex, fallback: "#FFFFFF")
                : "transparent"
            let iconColor = normalizedOverlayHex(overlay.iconColorHex, fallback: "#111111")
            let style = [
                basePositionStyle,
                "width:\(cssNumber(iconSizePercent))%;",
                "height:\(cssNumber(iconSizePercent))%;",
                rotationTransformStyle,
                "background:\(background);",
                "color:\(iconColor);",
                "border:1px solid rgba(17,17,17,0.08);"
            ].joined()
            return "<div class=\"edunode-overlay icon\" style=\"\(style)\">\(glyph)</div>"
        }

        let aspect = max(0.15, overlay.aspectRatio)
        let imageCornerRatio = cssNumber(max(0.0, min(0.5, overlay.imageCornerRadiusRatio)))
        let imageCornerRadiusExpr = "calc(min(\(cssNumber(widthPercent))%, \(cssNumber(heightPercent))%) * \(imageCornerRatio))"
        let imageStyle = [
            basePositionStyle,
            "width:\(cssNumber(widthPercent))%;",
            "height:\(cssNumber(heightPercent))%;",
            rotationTransformStyle,
            "aspect-ratio:\(cssNumber(Double(aspect)))/1;"
        ].joined()

        let filter = presentationImageCSSFilter(style: overlay.selectedFilter, params: overlay.stylization)
        if let svg = overlay.renderedSVGString, !svg.isEmpty {
            let backgroundHex = normalizedOverlayHex(overlay.vectorBackgroundColorHex, fallback: "#FFFFFF")
            let backgroundDisplay = overlay.vectorBackgroundVisible ? "block" : "none"
            return """
            <div class="edunode-overlay vector" style="\(imageStyle)">
              <div class="edunode-image-frame" style="border-radius:\(imageCornerRadiusExpr);">
                <div class="edunode-svg-bg" style="background:\(backgroundHex);display:\(backgroundDisplay);"></div>
                <div class="edunode-svg-ink" style="filter:\(filter);">
                  <div class="edunode-svg-wrap">\(svg)</div>
                </div>
              </div>
            </div>
            """
        }

        let imageData = overlay.displayImageData
        guard !imageData.isEmpty else { return nil }
        let dataURI = presentationImageDataURI(imageData)
        let pixelatedClass = overlay.selectedFilter == .pixelPainter ? " pixelated" : ""
        return "<div class=\"edunode-overlay image\(pixelatedClass)\" style=\"\(imageStyle)\"><div class=\"edunode-image-frame\" style=\"border-radius:\(imageCornerRadiusExpr);\"><img style=\"filter:\(filter);\" src=\"\(dataURI)\" alt=\"Overlay Image\"/></div></div>"
    }

    private func cssNumber(_ value: CGFloat) -> String {
        cssNumber(Double(value))
    }

    private func cssNumber(_ value: Double) -> String {
        String(format: "%.3f", value)
            .replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
    }

    private func normalizedOverlayHex(_ value: String, fallback: String) -> String {
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        if cleaned.count == 3 {
            cleaned = cleaned.map { "\($0)\($0)" }.joined()
        }
        guard cleaned.count == 6, Int(cleaned, radix: 16) != nil else {
            return fallback
        }
        return "#\(cleaned.uppercased())"
    }

    private func escapeOverlayHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func iconFallbackGlyph(systemName: String) -> String {
        let key = systemName.lowercased()
        if key.contains("wrench") { return "🛠︎" }
        if key.contains("star") { return "★" }
        if key.contains("book") { return "📘" }
        if key.contains("person") { return "👤" }
        if key.contains("photo") { return "🖼︎" }
        return "●"
    }

    private func mergeSlideGroupBackward(fileID: UUID, group: EduPresentationSlideGroup, slideCount: Int) {
        guard group.startIndex > 0 else { return }
        var breaks = effectivePresentationBreaks(fileID: fileID, slideCount: slideCount)
        breaks.remove(group.startIndex - 1)
        presentationBreaksByFile[fileID] = breaks
        persistPresentationState(fileID: fileID)
    }

    private func mergeSlideGroupForward(fileID: UUID, group: EduPresentationSlideGroup, slideCount: Int) {
        guard group.endIndex < slideCount - 1 else { return }
        var breaks = effectivePresentationBreaks(fileID: fileID, slideCount: slideCount)
        breaks.remove(group.endIndex)
        presentationBreaksByFile[fileID] = breaks
        persistPresentationState(fileID: fileID)
    }

    private func removeSlideGroupFromPresentation(fileID: UUID, group: EduPresentationSlideGroup) {
        guard !group.sourceSlides.isEmpty else { return }

        var excludedNodeIDs = presentationExcludedNodeIDsByFile[fileID] ?? Set<UUID>()
        for sourceSlide in group.sourceSlides {
            excludedNodeIDs.insert(sourceSlide.id)
        }
        presentationExcludedNodeIDsByFile[fileID] = excludedNodeIDs

        // Clear selection; the groups will be recomputed after this mutation.
        selectedPresentationGroupIDByFile[fileID] = nil

        guard activePresentationModeFileID == fileID,
              let file = workspaceFiles.first(where: { $0.id == fileID }) else { return }

        let rawDeck = EduPresentationPlanner.makeDeck(graphData: file.data)
        let filteredDeck = filteredPresentationDeck(for: fileID, from: rawDeck)
        if filteredDeck.orderedSlides.isEmpty {
            activePresentationModeFileID = nil
            if activePresentationStylingFileID == fileID {
                activePresentationStylingFileID = nil
            }
        } else if let firstGroup = presentationGroups(for: fileID, deck: filteredDeck).first {
            selectPresentationGroup(fileID: fileID, group: firstGroup)
        }
        persistPresentationState(fileID: fileID)
    }

    private func focusOnSlideGroup(_ group: EduPresentationSlideGroup) {
        cameraRequest = NodeEditorCameraRequest(canvasPosition: group.anchorPosition)
    }

    private func selectPresentationGroup(fileID: UUID, group: EduPresentationSlideGroup) {
        selectedPresentationGroupIDByFile[fileID] = group.id
        // Push camera update to next runloop so selection state settles first.
        DispatchQueue.main.async {
            focusOnSlideGroup(group)
        }
        persistPresentationState(fileID: fileID)
    }

    private func resolvedPresentationSelection(
        fileID: UUID,
        groups: [EduPresentationSlideGroup],
        slides: [EduPresentationComposedSlide]
    ) -> ResolvedPresentationSelection? {
        guard !groups.isEmpty, !slides.isEmpty else { return nil }

        let preferredID = selectedPresentationGroupIDByFile[fileID]
        let selectedIndex: Int
        if let preferredID,
           let index = groups.firstIndex(where: { $0.id == preferredID }) {
            selectedIndex = index
        } else {
            selectedIndex = 0
        }

        guard groups.indices.contains(selectedIndex),
              slides.indices.contains(selectedIndex) else {
            return nil
        }

        return ResolvedPresentationSelection(
            group: groups[selectedIndex],
            slide: slides[selectedIndex]
        )
    }

    @ViewBuilder
    private func presentationStylingOverlay(
        file: GNodeWorkspaceFile,
        selectedGroup: EduPresentationSlideGroup,
        selectedSlide: EduPresentationComposedSlide,
        toolbarTopPadding: CGFloat,
        bottomSafeInset: CGFloat
    ) -> some View {
        PresentationStylingOverlayView(
            courseName: file.name,
            slide: selectedSlide,
            stylingState: presentationStylingState(fileID: file.id, groupID: selectedGroup.id),
            pageStyle: resolvedPresentationPageStyle(fileID: file.id),
            textTheme: resolvedPresentationTextTheme(fileID: file.id),
            topPadding: toolbarTopPadding,
            bottomReservedHeight: max(228, 208 + bottomSafeInset),
            isChinese: isChineseUI(),
            onBack: {
                activePresentationStylingFileID = nil
            },
            onReset: {
                resetPresentationStyling(fileID: file.id, groupID: selectedGroup.id)
            },
            onUndo: {
                undoPresentationStyling(fileID: file.id, groupID: selectedGroup.id)
            },
            onRedo: {
                redoPresentationStyling(fileID: file.id, groupID: selectedGroup.id)
            },
            onInsertText: {
                insertPresentationTextOverlay(fileID: file.id, groupID: selectedGroup.id)
            },
            onInsertRoundedRect: {
                insertPresentationRoundedRectOverlay(fileID: file.id, groupID: selectedGroup.id)
            },
            onInsertImage: { data in
                insertPresentationOverlayImage(fileID: file.id, groupID: selectedGroup.id, imageData: data)
            },
            onClearSelection: {
                clearPresentationOverlaySelection(fileID: file.id, groupID: selectedGroup.id)
            },
            onSelectOverlay: { overlayID in
                selectPresentationOverlay(fileID: file.id, groupID: selectedGroup.id, overlayID: overlayID)
            },
            onMoveOverlay: { overlayID, center in
                movePresentationOverlay(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID,
                    center: center
                )
            },
            onRotateOverlay: { overlayID, deltaDegrees in
                rotatePresentationOverlay(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID,
                    deltaDegrees: deltaDegrees
                )
            },
            onUpdateImageOverlayFrame: { overlayID, center, normalizedWidth, normalizedHeight in
                updatePresentationImageOverlayFrame(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID,
                    center: center,
                    normalizedWidth: normalizedWidth,
                    normalizedHeight: normalizedHeight
                )
            },
            onScaleOverlay: { overlayID, scale in
                scalePresentationOverlay(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID,
                    scale: scale
                )
            },
            onCropOverlay: { overlayID, cropRect, handle in
                cropPresentationOverlay(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID,
                    normalizedRect: cropRect,
                    handleType: handle
                )
            },
            onDeleteOverlay: { overlayID in
                deletePresentationOverlay(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID
                )
            },
            onExtractSubject: { overlayID in
                extractPresentationOverlaySubject(fileID: file.id, groupID: selectedGroup.id, overlayID: overlayID)
            },
            onConvertToSVG: { overlayID in
                convertPresentationOverlayToSVG(fileID: file.id, groupID: selectedGroup.id, overlayID: overlayID)
            },
            onApplyFilter: { overlayID, style in
                applyPresentationOverlayFilter(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID,
                    style: style
                )
            },
            onUpdateStylization: { overlayID, stylization in
                updatePresentationOverlayStylization(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID,
                    stylization: stylization
                )
            },
            onUpdateImageVectorStyle: { overlayID, strokeHex, backgroundHex, backgroundVisible in
                updatePresentationImageVectorStyle(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID,
                    strokeHex: strokeHex,
                    backgroundHex: backgroundHex,
                    backgroundVisible: backgroundVisible
                )
            },
            onUpdateImageCornerRadius: { overlayID, cornerRadiusRatio in
                updatePresentationImageCornerRadius(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID,
                    cornerRadiusRatio: cornerRadiusRatio
                )
            },
            onApplyImageStyleToAll: { overlayID in
                applyPresentationImageStyleToAll(
                    fileID: file.id,
                    sourceGroupID: selectedGroup.id,
                    sourceOverlayID: overlayID
                )
            },
            onUpdateTextOverlay: { overlayID, editingState in
                updatePresentationTextOverlay(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID,
                    editingState: editingState
                )
            },
            onUpdateRoundedRectOverlay: { overlayID, editingState in
                updatePresentationRoundedRectOverlay(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID,
                    editingState: editingState
                )
            },
            onUpdateIconOverlay: { overlayID, editingState in
                updatePresentationIconOverlay(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    overlayID: overlayID,
                    editingState: editingState
                )
            },
            onUpdateTextTheme: { textTheme in
                updatePresentationTextTheme(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    textTheme: textTheme
                )
            },
            onUpdateNativeTextOverride: { element, style in
                updatePresentationNativeTextOverride(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    element: element,
                    style: style
                )
            },
            onUpdateNativeContentOverride: { element, content in
                updatePresentationNativeContentOverride(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    element: element,
                    content: content
                )
            },
            onUpdateNativeLayoutOverride: { element, layout in
                updatePresentationNativeLayoutOverride(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    element: element,
                    layout: layout
                )
            },
            onClearNativeTextOverrides: {
                clearPresentationNativeTextOverrides(
                    fileID: file.id,
                    groupID: selectedGroup.id
                )
            },
            onApplyTemplate: { template in
                applyPresentationTemplate(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    template: template
                )
            },
            onUpdatePageStyle: { pageStyle in
                updatePresentationPageStyle(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    pageStyle: pageStyle
                )
            },
            onUpdateVectorization: { settings in
                updatePresentationVectorizationSettings(
                    fileID: file.id,
                    groupID: selectedGroup.id,
                    settings: settings
                )
            }
        )
        .transition(.opacity)
    }

    private func presentationStylingState(fileID: UUID, groupID: UUID) -> PresentationSlideStylingState {
        var state = presentationStylingByFile[fileID]?[groupID] ?? .empty
        state.pageStyle = resolvedPresentationPageStyle(fileID: fileID)
        state.textTheme = resolvedPresentationTextTheme(fileID: fileID)
        return state
    }

    private func resolvedPresentationPageStyle(fileID: UUID) -> PresentationPageStyle {
        presentationPageStyleByFile[fileID] ?? .default
    }

    private func resolvedPresentationTextTheme(fileID: UUID) -> PresentationTextTheme {
        presentationTextThemeByFile[fileID] ?? .default
    }

    private func mutatePresentationStylingState(
        fileID: UUID,
        groupID: UUID,
        markTouched: Bool = true,
        _ mutate: (inout PresentationSlideStylingState) -> Void
    ) {
        var byGroup = presentationStylingByFile[fileID] ?? [:]
        var state = byGroup[groupID] ?? .empty
        mutate(&state)

        if state.overlays.isEmpty &&
            state.undoStack.isEmpty &&
            state.redoStack.isEmpty &&
            state.selectedOverlayID == nil &&
            state.vectorization == .default &&
            state.nativeTextOverrides.isEmpty &&
            state.nativeContentOverrides.isEmpty &&
            state.nativeLayoutOverrides.isEmpty &&
            state.pageStyle == .default &&
            state.textTheme == .default {
            byGroup.removeValue(forKey: groupID)
        } else {
            byGroup[groupID] = state
        }

        if byGroup.isEmpty {
            presentationStylingByFile.removeValue(forKey: fileID)
        } else {
            presentationStylingByFile[fileID] = byGroup
        }
        if markTouched {
            presentationStylingTouchedFileIDs.insert(fileID)
        }
    }

    private func pushPresentationStylingUndo(fileID: UUID, groupID: UUID) {
        let currentPageStyle = resolvedPresentationPageStyle(fileID: fileID)
        let currentTextTheme = resolvedPresentationTextTheme(fileID: fileID)
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            state.undoStack.append(
                PresentationStylingSnapshot(
                    overlays: state.overlays,
                    selectedOverlayID: state.selectedOverlayID,
                    vectorization: state.vectorization,
                    nativeTextOverrides: state.nativeTextOverrides,
                    nativeContentOverrides: state.nativeContentOverrides,
                    nativeLayoutOverrides: state.nativeLayoutOverrides,
                    pageStyle: currentPageStyle,
                    textTheme: currentTextTheme
                )
            )
            if state.undoStack.count > 40 {
                state.undoStack.removeFirst(state.undoStack.count - 40)
            }
            state.redoStack.removeAll()
        }
    }

    private func resetPresentationStyling(fileID: UUID, groupID: UUID) {
        let state = presentationStylingState(fileID: fileID, groupID: groupID)
        guard !state.overlays.isEmpty ||
                state.vectorization != .default ||
                !state.nativeTextOverrides.isEmpty ||
                !state.nativeContentOverrides.isEmpty ||
                !state.nativeLayoutOverrides.isEmpty ||
                state.pageStyle != .default ||
                state.textTheme != .default else { return }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { editableState in
            editableState.overlays.removeAll()
            editableState.selectedOverlayID = nil
            editableState.vectorization = .default
            editableState.nativeTextOverrides.removeAll()
            editableState.nativeContentOverrides.removeAll()
            editableState.nativeLayoutOverrides.removeAll()
            editableState.pageStyle = .default
            editableState.textTheme = .default
        }
        presentationPageStyleByFile.removeValue(forKey: fileID)
        presentationTextThemeByFile.removeValue(forKey: fileID)
        persistPresentationState(fileID: fileID)
    }

    private func undoPresentationStyling(fileID: UUID, groupID: UUID) {
        let currentPageStyle = resolvedPresentationPageStyle(fileID: fileID)
        let currentTextTheme = resolvedPresentationTextTheme(fileID: fileID)
        var restoredSnapshot: PresentationStylingSnapshot?
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            guard let previous = state.undoStack.popLast() else { return }
            state.redoStack.append(
                PresentationStylingSnapshot(
                    overlays: state.overlays,
                    selectedOverlayID: state.selectedOverlayID,
                    vectorization: state.vectorization,
                    nativeTextOverrides: state.nativeTextOverrides,
                    nativeContentOverrides: state.nativeContentOverrides,
                    nativeLayoutOverrides: state.nativeLayoutOverrides,
                    pageStyle: currentPageStyle,
                    textTheme: currentTextTheme
                )
            )
            if state.redoStack.count > 40 {
                state.redoStack.removeFirst(state.redoStack.count - 40)
            }
            state.overlays = previous.overlays
            state.selectedOverlayID = previous.selectedOverlayID
            state.vectorization = previous.vectorization
            state.nativeTextOverrides = previous.nativeTextOverrides
            state.nativeContentOverrides = previous.nativeContentOverrides
            state.nativeLayoutOverrides = previous.nativeLayoutOverrides
            if let selectedID = state.selectedOverlayID,
               !state.overlays.contains(where: { $0.id == selectedID }) {
                state.selectedOverlayID = state.overlays.last?.id
            }
            restoredSnapshot = previous
        }
        if let restoredSnapshot {
            presentationPageStyleByFile[fileID] = restoredSnapshot.pageStyle
            presentationTextThemeByFile[fileID] = restoredSnapshot.textTheme
        }
        persistPresentationState(fileID: fileID)
    }

    private func redoPresentationStyling(fileID: UUID, groupID: UUID) {
        let currentPageStyle = resolvedPresentationPageStyle(fileID: fileID)
        let currentTextTheme = resolvedPresentationTextTheme(fileID: fileID)
        var restoredSnapshot: PresentationStylingSnapshot?
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            guard let next = state.redoStack.popLast() else { return }
            state.undoStack.append(
                PresentationStylingSnapshot(
                    overlays: state.overlays,
                    selectedOverlayID: state.selectedOverlayID,
                    vectorization: state.vectorization,
                    nativeTextOverrides: state.nativeTextOverrides,
                    nativeContentOverrides: state.nativeContentOverrides,
                    nativeLayoutOverrides: state.nativeLayoutOverrides,
                    pageStyle: currentPageStyle,
                    textTheme: currentTextTheme
                )
            )
            if state.undoStack.count > 40 {
                state.undoStack.removeFirst(state.undoStack.count - 40)
            }
            state.overlays = next.overlays
            state.selectedOverlayID = next.selectedOverlayID
            state.vectorization = next.vectorization
            state.nativeTextOverrides = next.nativeTextOverrides
            state.nativeContentOverrides = next.nativeContentOverrides
            state.nativeLayoutOverrides = next.nativeLayoutOverrides
            if let selectedID = state.selectedOverlayID,
               !state.overlays.contains(where: { $0.id == selectedID }) {
                state.selectedOverlayID = state.overlays.last?.id
            }
            restoredSnapshot = next
        }
        if let restoredSnapshot {
            presentationPageStyleByFile[fileID] = restoredSnapshot.pageStyle
            presentationTextThemeByFile[fileID] = restoredSnapshot.textTheme
        }
        persistPresentationState(fileID: fileID)
    }

    private func insertPresentationOverlayImage(fileID: UUID, groupID: UUID, imageData: Data) {
        guard !imageData.isEmpty else { return }
        let storedImageData = normalizedPersistentImageData(imageData)
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            let imageCount = state.overlays.filter(\.isImage).count
            let col = imageCount % 4
            let row = imageCount / 4
            let centerX = min(0.82, 0.46 + CGFloat(col) * 0.1)
            let centerY = min(0.8, 0.48 + CGFloat(row % 3) * 0.1)
            let aspect = presentationOverlayAspectRatio(from: storedImageData)
            let slideAspect = max(0.75, resolvedPresentationPageStyle(fileID: fileID).aspectPreset.ratio)
            let targetHeight: CGFloat = 0.24
            let width = max(0.1, min(0.44, targetHeight * aspect / slideAspect))
            let overlay = PresentationSlideOverlay(
                imageData: storedImageData,
                selectedFilter: .original,
                center: CGPoint(x: centerX, y: centerY),
                normalizedWidth: width,
                normalizedHeight: presentationImageNormalizedHeight(
                    fileID: fileID,
                    normalizedWidth: width,
                    aspectRatio: aspect
                ),
                aspectRatio: aspect
            )
            state.overlays.append(overlay)
            state.selectedOverlayID = overlay.id
        }
        persistPresentationState(fileID: fileID)
    }

    private func insertPresentationTextOverlay(fileID: UUID, groupID: UUID) {
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        let h2Style = resolvedPresentationTextTheme(fileID: fileID).style(for: .h2)
        let h2FontSize = max(14, min(96, h2Style.sizeCqw * 13.66))
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            var overlay = PresentationSlideOverlay.makeText(
                center: CGPoint(x: 0.5, y: 0.6)
            )
            overlay.textStylePreset = .h2
            overlay.textColorHex = h2Style.colorHex
            overlay.textWeightValue = h2Style.weightValue
            overlay.textFontSize = h2FontSize
            state.overlays.append(overlay)
            state.selectedOverlayID = overlay.id
        }
        persistPresentationState(fileID: fileID)
    }

    private func insertPresentationRoundedRectOverlay(fileID: UUID, groupID: UUID) {
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            let overlay = PresentationSlideOverlay.makeRoundedRect(
                center: CGPoint(x: 0.5, y: 0.6)
            )
            state.overlays.append(overlay)
            state.selectedOverlayID = overlay.id
        }
        persistPresentationState(fileID: fileID)
    }

    private func insertPresentationIconOverlay(fileID: UUID, groupID: UUID) {
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            let overlay = PresentationSlideOverlay.makeIcon(
                center: CGPoint(x: 0.5, y: 0.6)
            )
            state.overlays.append(overlay)
            state.selectedOverlayID = overlay.id
        }
        persistPresentationState(fileID: fileID)
    }

    private func selectPresentationOverlay(fileID: UUID, groupID: UUID, overlayID: UUID) {
        mutatePresentationStylingState(fileID: fileID, groupID: groupID, markTouched: false) { state in
            guard state.overlays.contains(where: { $0.id == overlayID }) else { return }
            state.selectedOverlayID = overlayID
        }
        persistPresentationState(fileID: fileID)
    }

    private func clearPresentationOverlaySelection(fileID: UUID, groupID: UUID) {
        mutatePresentationStylingState(fileID: fileID, groupID: groupID, markTouched: false) { state in
            state.selectedOverlayID = nil
        }
        persistPresentationState(fileID: fileID)
    }

    private func applyPresentationOverlayFilter(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        style: SVGFilterStyle
    ) {
        let state = presentationStylingState(fileID: fileID, groupID: groupID)
        guard let overlay = state.overlays.first(where: { $0.id == overlayID }),
              overlay.isImage,
              overlay.vectorDocument != nil,
              overlay.selectedFilter != style else {
            return
        }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            editable.selectedFilter = style
        }
        persistPresentationState(fileID: fileID)
    }

    private func movePresentationOverlay(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        center: CGPoint
    ) {
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            editable.center = center
        }
        persistPresentationState(fileID: fileID)
    }

    private func rotatePresentationOverlay(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        deltaDegrees: Double
    ) {
        guard deltaDegrees.isFinite, abs(deltaDegrees) > 0.05 else { return }
        let state = presentationStylingState(fileID: fileID, groupID: groupID)
        guard let overlay = state.overlays.first(where: { $0.id == overlayID }),
              overlay.isImage else {
            return
        }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            editable.rotationDegrees = normalizedRotationDegrees(editable.rotationDegrees + deltaDegrees)
        }
        persistPresentationState(fileID: fileID)
    }

    private func scalePresentationOverlay(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        scale: CGFloat
    ) {
        guard scale.isFinite else { return }
        let clampedScale = max(0.5, min(2.4, scale))
        guard abs(clampedScale - 1) > 0.01 else { return }

        let state = presentationStylingState(fileID: fileID, groupID: groupID)
        guard state.overlays.contains(where: { $0.id == overlayID }) else { return }

        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            let scaledWidth = editable.normalizedWidth * clampedScale
            editable.normalizedWidth = max(0.08, min(0.9, scaledWidth))
            if editable.isIcon {
                editable.normalizedHeight = editable.normalizedWidth
                editable.aspectRatio = 1
            } else if editable.isImage {
                editable.normalizedHeight = presentationImageNormalizedHeight(
                    fileID: fileID,
                    normalizedWidth: editable.normalizedWidth,
                    aspectRatio: editable.aspectRatio
                )
            } else if editable.isText || editable.isRoundedRect {
                let scaledHeight = editable.normalizedHeight * clampedScale
                editable.normalizedHeight = max(0.08, min(0.72, scaledHeight))
                editable.aspectRatio = max(0.15, editable.normalizedWidth / max(editable.normalizedHeight, 0.01))
            }
        }
        persistPresentationState(fileID: fileID)
    }

    private func cropPresentationOverlay(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        normalizedRect: CGRect,
        handleType: String? = nil
    ) {
        let state = presentationStylingState(fileID: fileID, groupID: groupID)
        guard let overlay = state.overlays.first(where: { $0.id == overlayID }),
              overlay.isImage else {
            return
        }

        let relativeRect = normalizedRect
        let currentCropRect = normalizedUnitCropRect(overlay.cumulativeCropRect)
        let nextCropRect = composedCropRect(current: currentCropRect, relative: relativeRect)
        guard nextCropRect.width > 0.02, nextCropRect.height > 0.02 else { return }

        let cropSourceData = overlay.cropSourceImageData ?? overlay.displayImageData
        guard let croppedData = cropImageData(cropSourceData, normalizedRect: nextCropRect) else { return }
        let persistedCroppedData = normalizedPersistentImageData(croppedData)
        let persistedCropSourceData = normalizedPersistentImageData(cropSourceData)
        let wasVectorized = overlay.vectorDocument != nil
        let preservedFilter = overlay.selectedFilter
        let vectorizationOptions = state.vectorization.svgOptions
        let currentWidth = max(0.08, min(0.92, overlay.normalizedWidth))
        let currentHeight = max(0.08, min(0.92, overlay.normalizedHeight))
        let slideAspect = max(0.75, resolvedPresentationPageStyle(fileID: fileID).aspectPreset.ratio)
        let oldLeft = overlay.center.x - currentWidth * 0.5
        let oldRight = overlay.center.x + currentWidth * 0.5
        let oldTop = overlay.center.y - currentHeight * 0.5
        let oldBottom = overlay.center.y + currentHeight * 0.5

        let nextAspect = presentationOverlayAspectRatio(from: persistedCroppedData)
        var nextWidth = currentWidth
        var nextHeight = currentHeight
        var anchoredCenter = overlay.center
        let normalizedHandle = handleType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let analysisRect = normalizedCropRect(relativeRect)
        let epsilon = 0.0001
        let nearFullWidth = analysisRect.origin.x <= epsilon && abs(analysisRect.width - 1) <= 0.002
        let nearFullHeight = analysisRect.origin.y <= epsilon && abs(analysisRect.height - 1) <= 0.002
        let resolvedHandle: String = {
            guard !normalizedHandle.isEmpty else {
                // Backward compatibility with legacy crop payloads that do not include handle info.
                if analysisRect.origin.x > epsilon && nearFullHeight {
                    return "crop-left"
                }
                if analysisRect.width < 0.999 && analysisRect.origin.x <= epsilon && nearFullHeight {
                    return "crop-right"
                }
                if analysisRect.origin.y > epsilon && nearFullWidth {
                    return "crop-top"
                }
                if analysisRect.height < 0.999 && analysisRect.origin.y <= epsilon && nearFullWidth {
                    return "crop-bottom"
                }
                return ""
            }
            return normalizedHandle
        }()

        if resolvedHandle == "crop-left" || resolvedHandle == "crop-right" {
            let estimatedWidth = currentHeight * nextAspect / max(0.75, slideAspect)
            nextWidth = max(0.08, min(0.92, estimatedWidth))
            nextHeight = currentHeight

            if resolvedHandle == "crop-left" {
                anchoredCenter.x = oldRight - nextWidth * 0.5
            } else {
                anchoredCenter.x = oldLeft + nextWidth * 0.5
            }
        } else if resolvedHandle == "crop-top" || resolvedHandle == "crop-bottom" {
            nextWidth = currentWidth
            nextHeight = presentationImageNormalizedHeight(
                fileID: fileID,
                normalizedWidth: nextWidth,
                aspectRatio: nextAspect
            )

            if resolvedHandle == "crop-bottom" {
                anchoredCenter.y = oldTop + nextHeight * 0.5
            } else {
                anchoredCenter.y = oldBottom - nextHeight * 0.5
            }
        } else {
            // Generic crop (e.g. panel input) keeps width stable and recomputes height.
            nextWidth = currentWidth
            nextHeight = presentationImageNormalizedHeight(
                fileID: fileID,
                normalizedWidth: nextWidth,
                aspectRatio: nextAspect
            )
        }

        let minCenterX = max(0.04, nextWidth * 0.5)
        let maxCenterX = min(0.96, 1.0 - nextWidth * 0.5)
        if minCenterX <= maxCenterX {
            anchoredCenter.x = max(minCenterX, min(maxCenterX, anchoredCenter.x))
        } else {
            anchoredCenter.x = max(0.04, min(0.96, anchoredCenter.x))
        }
        let minCenterY = max(0.08, nextHeight * 0.5)
        let maxCenterY = min(0.92, 1.0 - nextHeight * 0.5)
        if minCenterY <= maxCenterY {
            anchoredCenter.y = max(minCenterY, min(maxCenterY, anchoredCenter.y))
        } else {
            anchoredCenter.y = max(0.08, min(0.92, anchoredCenter.y))
        }

        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            if editable.extractedImageData != nil {
                editable.extractedImageData = persistedCroppedData
            } else {
                editable.imageData = persistedCroppedData
            }
            editable.cropSourceImageData = persistedCropSourceData
            editable.cumulativeCropRect = nextCropRect
            editable.center = anchoredCenter
            editable.normalizedWidth = nextWidth
            editable.aspectRatio = nextAspect
            editable.normalizedHeight = nextHeight
            if wasVectorized {
                editable.selectedFilter = preservedFilter
            } else {
                editable.vectorDocument = nil
                editable.selectedFilter = .original
            }
        }
        persistPresentationState(fileID: fileID)

        if wasVectorized {
            rebuildPresentationOverlaySVG(
                fileID: fileID,
                groupID: groupID,
                overlayID: overlayID,
                sourceData: persistedCroppedData,
                options: vectorizationOptions,
                resetFilterToOriginal: false
            )
        }
    }

    private func updatePresentationImageOverlayFrame(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        center: CGPoint,
        normalizedWidth: CGFloat,
        normalizedHeight: CGFloat
    ) {
        let state = presentationStylingState(fileID: fileID, groupID: groupID)
        guard let overlay = state.overlays.first(where: { $0.id == overlayID }),
              overlay.isImage else {
            return
        }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            editable.center = CGPoint(
                x: max(0.04, min(0.96, center.x)),
                y: max(0.08, min(0.92, center.y))
            )
            let width = max(0.08, min(0.92, normalizedWidth))
            let height = max(0.08, min(0.92, normalizedHeight))
            editable.normalizedWidth = width
            editable.normalizedHeight = height

            let slideAspect = max(0.75, resolvedPresentationPageStyle(fileID: fileID).aspectPreset.ratio)
            let derivedAspect = width * slideAspect / max(0.08, height)
            if derivedAspect.isFinite {
                editable.aspectRatio = max(0.15, min(12, derivedAspect))
            } else {
                editable.aspectRatio = max(0.15, editable.aspectRatio)
            }
        }
        persistPresentationState(fileID: fileID)
    }

    private func deletePresentationOverlay(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID
    ) {
        let state = presentationStylingState(fileID: fileID, groupID: groupID)
        guard state.overlays.contains(where: { $0.id == overlayID }) else { return }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { editableState in
            editableState.overlays.removeAll { $0.id == overlayID }
            if editableState.selectedOverlayID == overlayID {
                editableState.selectedOverlayID = editableState.overlays.last?.id
            }
        }
        persistPresentationState(fileID: fileID)
    }

    private func updatePresentationOverlayStylization(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        stylization: SVGStylizationParameters
    ) {
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            guard editable.isImage else { return }
            editable.stylization = stylization
        }
        persistPresentationState(fileID: fileID)
    }

    private func updatePresentationImageVectorStyle(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        strokeHex: String,
        backgroundHex: String,
        backgroundVisible: Bool
    ) {
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            guard editable.isImage else { return }
            editable.vectorStrokeColorHex = strokeHex
            editable.vectorBackgroundColorHex = backgroundHex
            editable.vectorBackgroundVisible = backgroundVisible
        }
        persistPresentationState(fileID: fileID)
    }

    private func updatePresentationImageCornerRadius(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        cornerRadiusRatio: Double
    ) {
        let clamped = max(0, min(0.5, cornerRadiusRatio))
        let state = presentationStylingState(fileID: fileID, groupID: groupID)
        guard let overlay = state.overlays.first(where: { $0.id == overlayID }),
              overlay.isImage else {
            return
        }
        guard abs(overlay.imageCornerRadiusRatio - clamped) > 0.0005 else { return }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            guard editable.isImage else { return }
            editable.imageCornerRadiusRatio = clamped
        }
        persistPresentationState(fileID: fileID)
    }

    private func applyPresentationImageStyleToAll(
        fileID: UUID,
        sourceGroupID: UUID,
        sourceOverlayID: UUID
    ) {
        guard var byGroup = presentationStylingByFile[fileID],
              let sourceState = byGroup[sourceGroupID],
              let sourceOverlay = sourceState.overlays.first(where: { $0.id == sourceOverlayID && $0.isImage }),
              sourceOverlay.vectorDocument != nil else {
            return
        }

        let sourceFilter = sourceOverlay.selectedFilter
        let sourceStylization = sourceOverlay.stylization
        let sourceStroke = sourceOverlay.vectorStrokeColorHex
        let sourceBackground = sourceOverlay.vectorBackgroundColorHex
        let sourceBackgroundVisible = sourceOverlay.vectorBackgroundVisible
        let sourceCornerRadius = sourceOverlay.imageCornerRadiusRatio
        let sourceVectorization = sourceState.vectorization

        var pendingRevectorization: [(groupID: UUID, overlayID: UUID, sourceData: Data)] = []

        for (groupID, var state) in byGroup {
            state.vectorization = sourceVectorization
            for index in state.overlays.indices {
                guard state.overlays[index].isImage else { continue }
                if groupID == sourceGroupID && state.overlays[index].id == sourceOverlayID {
                    continue
                }

                state.overlays[index].selectedFilter = sourceFilter
                state.overlays[index].stylization = sourceStylization
                state.overlays[index].vectorStrokeColorHex = sourceStroke
                state.overlays[index].vectorBackgroundColorHex = sourceBackground
                state.overlays[index].vectorBackgroundVisible = sourceBackgroundVisible
                state.overlays[index].imageCornerRadiusRatio = sourceCornerRadius

                if state.overlays[index].vectorDocument == nil {
                    pendingRevectorization.append((
                        groupID: groupID,
                        overlayID: state.overlays[index].id,
                        sourceData: state.overlays[index].displayImageData
                    ))
                }
            }
            byGroup[groupID] = state
        }

        presentationStylingByFile[fileID] = byGroup
        persistPresentationState(fileID: fileID)

        for pending in pendingRevectorization {
            rebuildPresentationOverlaySVG(
                fileID: fileID,
                groupID: pending.groupID,
                overlayID: pending.overlayID,
                sourceData: pending.sourceData,
                options: sourceVectorization.svgOptions,
                resetFilterToOriginal: false
            )
        }
    }

    private func updatePresentationTextOverlay(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        editingState: PresentationTextEditingState
    ) {
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            guard editable.isText else { return }
            editable.textEditingState = editingState
            editable.aspectRatio = max(0.15, editable.normalizedWidth / max(editable.normalizedHeight, 0.01))
        }
        persistPresentationState(fileID: fileID)
    }

    private func updatePresentationRoundedRectOverlay(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        editingState: PresentationRoundedRectEditingState
    ) {
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            guard editable.isRoundedRect else { return }
            editable.roundedRectEditingState = editingState
        }
        persistPresentationState(fileID: fileID)
    }

    private func updatePresentationIconOverlay(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        editingState: PresentationIconEditingState
    ) {
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            guard editable.isIcon else { return }
            editable.iconEditingState = editingState
        }
        persistPresentationState(fileID: fileID)
    }

    private func updatePresentationPageStyle(
        fileID: UUID,
        groupID: UUID,
        pageStyle: PresentationPageStyle
    ) {
        let current = resolvedPresentationPageStyle(fileID: fileID)
        guard current != pageStyle else { return }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        presentationPageStyleByFile[fileID] = pageStyle
        presentationStylingTouchedFileIDs.insert(fileID)
        persistPresentationState(fileID: fileID)
    }

    private func updatePresentationTextTheme(
        fileID: UUID,
        groupID: UUID,
        textTheme: PresentationTextTheme
    ) {
        let current = resolvedPresentationTextTheme(fileID: fileID)
        guard current != textTheme else { return }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        presentationTextThemeByFile[fileID] = textTheme
        presentationStylingTouchedFileIDs.insert(fileID)
        persistPresentationState(fileID: fileID)
    }

    private func updatePresentationNativeTextOverride(
        fileID: UUID,
        groupID: UUID,
        element: PresentationNativeElement,
        style: PresentationTextStyleConfig?
    ) {
        let currentState = presentationStylingState(fileID: fileID, groupID: groupID)
        let currentValue = currentState.nativeTextOverrides[element]
        if currentValue == style { return }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            if let style {
                state.nativeTextOverrides[element] = style
            } else {
                state.nativeTextOverrides.removeValue(forKey: element)
            }
        }
        persistPresentationState(fileID: fileID)
    }

    private func updatePresentationNativeContentOverride(
        fileID: UUID,
        groupID: UUID,
        element: PresentationNativeElement,
        content: String?
    ) {
        let normalized: String? = content?.replacingOccurrences(of: "\r\n", with: "\n")
        let currentState = presentationStylingState(fileID: fileID, groupID: groupID)
        let currentValue = currentState.nativeContentOverrides[element]
        if currentValue == normalized { return }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            if let normalized {
                state.nativeContentOverrides[element] = normalized
            } else {
                state.nativeContentOverrides.removeValue(forKey: element)
            }
        }
        persistPresentationState(fileID: fileID)
    }

    private func updatePresentationNativeLayoutOverride(
        fileID: UUID,
        groupID: UUID,
        element: PresentationNativeElement,
        layout: PresentationNativeLayoutOverride?
    ) {
        let clampedLayout = layout?.clamped()
        let nextValue: PresentationNativeLayoutOverride? = {
            if let clampedLayout, !clampedLayout.isZero {
                return clampedLayout
            }
            return nil
        }()
        let currentState = presentationStylingState(fileID: fileID, groupID: groupID)
        let currentValue = currentState.nativeLayoutOverrides[element]
        if currentValue == nextValue { return }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            if let nextValue {
                state.nativeLayoutOverrides[element] = nextValue
            } else {
                state.nativeLayoutOverrides.removeValue(forKey: element)
            }
        }
        persistPresentationState(fileID: fileID)
    }

    private func clearPresentationNativeTextOverrides(
        fileID: UUID,
        groupID: UUID
    ) {
        let currentState = presentationStylingState(fileID: fileID, groupID: groupID)
        guard !currentState.nativeTextOverrides.isEmpty else { return }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            state.nativeTextOverrides.removeAll()
        }
        persistPresentationState(fileID: fileID)
    }

    private func applyPresentationTemplate(
        fileID: UUID,
        groupID: UUID,
        template: PresentationThemeTemplate
    ) {
        let aspect = resolvedPresentationPageStyle(fileID: fileID).aspectPreset
        var nextStyle = template.pageStyle
        nextStyle.aspectPreset = aspect
        let nextTextTheme = template.textTheme
        let currentStyle = resolvedPresentationPageStyle(fileID: fileID)
        let currentTextTheme = resolvedPresentationTextTheme(fileID: fileID)
        guard currentStyle != nextStyle || currentTextTheme != nextTextTheme else { return }
        pushPresentationStylingUndo(fileID: fileID, groupID: groupID)
        presentationPageStyleByFile[fileID] = nextStyle
        presentationTextThemeByFile[fileID] = nextTextTheme
        presentationStylingTouchedFileIDs.insert(fileID)
        persistPresentationState(fileID: fileID)
    }

    private func updatePresentationOverlay(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        _ mutate: (inout PresentationSlideOverlay) -> Void
    ) {
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            guard let index = state.overlays.firstIndex(where: { $0.id == overlayID }) else { return }
            mutate(&state.overlays[index])
        }
    }

    private func updatePresentationVectorizationSettings(
        fileID: UUID,
        groupID: UUID,
        settings: PresentationVectorizationSettings
    ) {
        let previousState = presentationStylingState(fileID: fileID, groupID: groupID)
        mutatePresentationStylingState(fileID: fileID, groupID: groupID) { state in
            state.vectorization = settings
        }
        if let selectedID = previousState.selectedOverlayID,
           let overlay = previousState.overlays.first(where: { $0.id == selectedID }),
           overlay.isImage,
           overlay.vectorDocument != nil {
            rebuildPresentationOverlaySVG(
                fileID: fileID,
                groupID: groupID,
                overlayID: selectedID,
                sourceData: overlay.displayImageData,
                options: settings.svgOptions,
                resetFilterToOriginal: false
            )
        }
        persistPresentationState(fileID: fileID)
    }

    private func extractPresentationOverlaySubject(fileID: UUID, groupID: UUID, overlayID: UUID) {
        let state = presentationStylingState(fileID: fileID, groupID: groupID)
        guard let overlay = state.overlays.first(where: { $0.id == overlayID }),
              overlay.isImage,
              !overlay.isExtracting else {
            return
        }

        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            editable.isExtracting = true
            editable.activeVectorizationRequestID = nil
        }
        persistPresentationState(fileID: fileID)

        Task {
            let extractedImageData = await presentationOverlayExtractedSubject(imageData: overlay.imageData)
            await MainActor.run {
                updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
                    editable.isExtracting = false
                    editable.activeVectorizationRequestID = nil
                    if let extractedImageData {
                        let persistedExtractedData = normalizedPersistentImageData(extractedImageData)
                        editable.extractedImageData = persistedExtractedData
                        editable.cropSourceImageData = nil
                        editable.cumulativeCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                        editable.aspectRatio = presentationOverlayAspectRatio(from: persistedExtractedData)
                        editable.normalizedHeight = presentationImageNormalizedHeight(
                            fileID: fileID,
                            normalizedWidth: editable.normalizedWidth,
                            aspectRatio: editable.aspectRatio
                        )
                        // Subject extraction should stay in bitmap mode until user taps Convert to SVG.
                        editable.vectorDocument = nil
                        editable.selectedFilter = .original
                    }
                }
                persistPresentationState(fileID: fileID)
            }
        }
    }

    private func presentationOverlayExtractedSubject(imageData: Data) async -> Data? {
        #if canImport(UIKit) && canImport(CoreImage)
        if let sourceImage = UIImage(data: imageData),
           let extractedImage = await PresentationSubjectExtractor.extractSubject(from: sourceImage),
           let extractedPNG = extractedImage.pngData() {
            return extractedPNG
        }
        #endif
        return nil
    }

    private func convertPresentationOverlayToSVG(fileID: UUID, groupID: UUID, overlayID: UUID) {
        let state = presentationStylingState(fileID: fileID, groupID: groupID)
        guard let overlay = state.overlays.first(where: { $0.id == overlayID }),
              overlay.isImage else {
            return
        }

        rebuildPresentationOverlaySVG(
            fileID: fileID,
            groupID: groupID,
            overlayID: overlayID,
            sourceData: overlay.displayImageData,
            options: state.vectorization.svgOptions,
            resetFilterToOriginal: true
        )
    }

    private func rebuildPresentationOverlaySVG(
        fileID: UUID,
        groupID: UUID,
        overlayID: UUID,
        sourceData: Data,
        options: SVGVectorizationOptions,
        resetFilterToOriginal: Bool
    ) {
        let requestID = UUID()
        updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
            editable.isExtracting = true
            editable.activeVectorizationRequestID = requestID
        }
        persistPresentationState(fileID: fileID)

        Task {
            let document = try? SVGBitmapConverter.vectorize(imageData: sourceData, options: options)

            await MainActor.run {
                updatePresentationOverlay(fileID: fileID, groupID: groupID, overlayID: overlayID) { editable in
                    guard editable.activeVectorizationRequestID == requestID else { return }
                    editable.isExtracting = false
                    editable.activeVectorizationRequestID = nil
                    guard let document else { return }
                    editable.vectorDocument = document
                    if resetFilterToOriginal {
                        editable.selectedFilter = .original
                    }
                }
                persistPresentationState(fileID: fileID)
            }
        }
    }

    private func presentationOverlayAspectRatio(from imageData: Data) -> CGFloat {
        if let preciseAspect = presentationDisplayAspectRatio(from: imageData) {
            return preciseAspect
        }
        #if canImport(UIKit)
        if let image = UIImage(data: imageData),
           image.size.height > 0 {
            return max(0.15, image.size.width / image.size.height)
        }
        #endif
        return 1
    }

    private func presentationDisplayAspectRatio(from imageData: Data) -> CGFloat? {
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let rawWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue
            ?? (properties[kCGImagePropertyPixelWidth] as? Double)
        let rawHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue
            ?? (properties[kCGImagePropertyPixelHeight] as? Double)
        guard let rawWidth, let rawHeight, rawWidth > 0, rawHeight > 0 else {
            return nil
        }

        var width = CGFloat(rawWidth)
        var height = CGFloat(rawHeight)
        let orientationValue = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue
            ?? (properties[kCGImagePropertyOrientation] as? Int)
            ?? 1
        if orientationValue == 5 || orientationValue == 6 || orientationValue == 7 || orientationValue == 8 {
            swap(&width, &height)
        }
        guard height > 0 else { return nil }
        return max(0.15, width / height)
        #else
        _ = imageData
        return nil
        #endif
    }

    private func presentationImageNormalizedHeight(
        fileID: UUID,
        normalizedWidth: CGFloat,
        aspectRatio: CGFloat
    ) -> CGFloat {
        let slideAspect = max(0.75, resolvedPresentationPageStyle(fileID: fileID).aspectPreset.ratio)
        let normalized = normalizedWidth * slideAspect / max(0.15, aspectRatio)
        return max(0.08, min(0.92, normalized))
    }

    private func normalizedRotationDegrees(_ value: Double) -> Double {
        var next = value.truncatingRemainder(dividingBy: 360)
        if next <= -180 { next += 360 }
        if next > 180 { next -= 360 }
        return next
    }

    private func normalizedCropRect(_ rect: CGRect) -> CGRect {
        normalizedUnitCropRect(rect)
    }

    private func normalizedUnitCropRect(_ rect: CGRect) -> CGRect {
        let minSize: CGFloat = 0.02
        var x = rect.origin.x
        var y = rect.origin.y
        var width = rect.size.width
        var height = rect.size.height

        if x < 0 {
            width += x
            x = 0
        }
        if y < 0 {
            height += y
            y = 0
        }
        if x + width > 1 {
            width = 1 - x
        }
        if y + height > 1 {
            height = 1 - y
        }

        width = max(minSize, min(1, width))
        height = max(minSize, min(1, height))
        x = min(max(0, x), 1 - width)
        y = min(max(0, y), 1 - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func composedCropRect(current: CGRect, relative: CGRect) -> CGRect {
        let currentRect = normalizedUnitCropRect(current)
        let composed = CGRect(
            x: currentRect.origin.x + relative.origin.x * currentRect.width,
            y: currentRect.origin.y + relative.origin.y * currentRect.height,
            width: currentRect.width * relative.width,
            height: currentRect.height * relative.height
        )
        return normalizedUnitCropRect(composed)
    }

    private func cropImageData(_ imageData: Data, normalizedRect: CGRect) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            return nil
        }

        let clamped = normalizedCropRect(normalizedRect)
        let pixelRect = CGRect(
            x: CGFloat(cgImage.width) * clamped.origin.x,
            y: CGFloat(cgImage.height) * clamped.origin.y,
            width: CGFloat(cgImage.width) * clamped.width,
            height: CGFloat(cgImage.height) * clamped.height
        ).integral

        guard pixelRect.width > 1, pixelRect.height > 1,
              let cropped = cgImage.cropping(to: pixelRect) else {
            return nil
        }

        let output = UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
        return output.pngData()
        #else
        _ = imageData
        _ = normalizedRect
        return nil
        #endif
    }

    private func togglePresentationStylingMode(
        fileID: UUID,
        groups: [EduPresentationSlideGroup],
        selectedGroupID: UUID?
    ) {
        if let file = workspaceFiles.first(where: { $0.id == fileID }) {
            hydratePresentationState(for: file, force: true)
        }
        if activePresentationStylingFileID == fileID {
            activePresentationStylingFileID = nil
            return
        }

        activePresentationStylingFileID = fileID
        if let target = groups.first(where: { $0.id == selectedGroupID }) ?? groups.first {
            selectPresentationGroup(fileID: fileID, group: target)
        }
    }

    @ViewBuilder
    private func presentationStylingEntryButton(
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Image(systemName: "paintpalette")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.96))
            }
            .frame(width: 58, height: 58)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(
                Circle()
                    .fill(Color.black.opacity(isActive ? 0.36 : 0.28))
            )
            .overlay(
                ZStack {
                    AnimatedGradientRing(lineWidth: isActive ? 3.6 : 3.0)
                        .blur(radius: isActive ? 4.6 : 3.6)
                        .opacity(isActive ? 0.95 : 0.78)
                    AnimatedGradientRing(lineWidth: isActive ? 2.2 : 1.8)
                        .opacity(0.82)
                }
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(isActive ? 0.22 : 0.14), lineWidth: 0.9)
                    .blur(radius: 0.6)
            )
            .overlay(
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(isActive ? 0.24 : 0.16),
                                Color.white.opacity(0)
                            ],
                            center: .center,
                            startRadius: 6,
                            endRadius: 33
                        )
                    )
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.26), radius: 9, y: 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func presentationTrackingPanel(
        file: GNodeWorkspaceFile,
        groups: [EduPresentationSlideGroup],
        topPadding: CGFloat
    ) -> some View {
        if let summary = presentationTrackingSummary(file: file, groups: groups) {
            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(summary.isChinese ? "课程追踪" : "Course Tracking")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("\(summary.currentPage)/\(summary.totalPages)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        BloomLevelChartView(chips: summary.levelChips, isChinese: summary.isChinese)

                        if summary.activeEvaluationNodes.isEmpty {
                            Text(
                                summary.isChinese
                                    ? "当前页面未连接 Evaluation 节点。"
                                    : "No Evaluation node linked to current page."
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else if summary.studentNames.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Button {
                                    openStudentRosterEditor(for: file)
                                } label: {
                                    Label(
                                        summary.isChinese ? "配置学生名单" : "Configure Student Roster",
                                        systemImage: "person.2.badge.plus"
                                    )
                                    .font(.caption2.weight(.semibold))
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.orange.opacity(0.18))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                                )

                                Text(
                                    summary.isChinese
                                        ? "请配置学生名单才能进行评价功能。"
                                        : "Configure student roster to enable scoring."
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            Button {
                                presentationEvaluationSheetContext = PresentationEvaluationSheetContext(
                                    fileName: file.name,
                                    evaluationNodes: summary.activeEvaluationNodes,
                                    studentNames: summary.studentNames,
                                    isChinese: summary.isChinese
                                )
                            } label: {
                                Label(
                                    summary.isChinese
                                        ? "打开评价打分"
                                        : "Open Scoring",
                                    systemImage: "checklist"
                                )
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.18))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .frame(maxWidth: 360, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)
                }
                .padding(.top, topPadding)
                .padding(.leading, splitVisibility == .detailOnly ? 72 : 16)
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea(edges: .top)
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    private func presentationTrackingSummary(
        file: GNodeWorkspaceFile,
        groups: [EduPresentationSlideGroup]
    ) -> PresentationTrackingSummary? {
        guard !groups.isEmpty else { return nil }
        let index = selectedPresentationGroupIndex(fileID: file.id, groups: groups)
        let currentGroup = groups[index]
        let isChinese = isChineseUI()
        let studentNames = parsedStudentNames(from: file.studentProfile)

        guard let document = try? decodeDocument(from: file.data) else {
            return PresentationTrackingSummary(
                currentPage: index + 1,
                totalPages: groups.count,
                levelChips: defaultKnowledgeLevelCountChips(),
                activeEvaluationNodes: [],
                studentNames: studentNames,
                isChinese: isChinese
            )
        }

        let nodeByID = Dictionary(uniqueKeysWithValues: document.nodes.map { ($0.id, $0) })
        let stateByNodeID = Dictionary(uniqueKeysWithValues: document.canvasState.map { ($0.nodeID, $0) })
        let nodeTypeByID = Dictionary(uniqueKeysWithValues: document.nodes.map { ($0.id, $0.nodeType) })
        var outgoingByNode: [UUID: [UUID]] = [:]
        for connection in document.connections {
            outgoingByNode[connection.sourceNodeID, default: []].append(connection.targetNodeID)
        }

        let startNodeIDs = Set(currentGroup.sourceSlides.map(\.id))
        let reachableEvaluationIDs = reachableEvaluationNodeIDs(
            from: startNodeIDs,
            outgoingByNode: outgoingByNode,
            nodeTypeByID: nodeTypeByID
        )

        let sortedEvaluationIDs = reachableEvaluationIDs.sorted { lhs, rhs in
            let lhsState = stateByNodeID[lhs]
            let rhsState = stateByNodeID[rhs]
            let lx = lhsState?.positionX ?? 0
            let rx = rhsState?.positionX ?? 0
            if abs(lx - rx) > 0.5 { return lx < rx }
            let ly = lhsState?.positionY ?? 0
            let ry = rhsState?.positionY ?? 0
            if abs(ly - ry) > 0.5 { return ly < ry }
            return lhs.uuidString < rhs.uuidString
        }

        let evaluationDescriptors = sortedEvaluationIDs.compactMap { nodeID -> EvaluationNodeDescriptor? in
            guard let node = nodeByID[nodeID] else { return nil }
            let customName = stateByNodeID[nodeID]?.customName
            return evaluationDescriptor(for: node, customName: customName)
        }

        return PresentationTrackingSummary(
            currentPage: index + 1,
            totalPages: groups.count,
            levelChips: knowledgeLevelCountChips(from: document),
            activeEvaluationNodes: evaluationDescriptors,
            studentNames: studentNames,
            isChinese: isChinese
        )
    }

    private func selectedPresentationGroupIndex(
        fileID: UUID,
        groups: [EduPresentationSlideGroup]
    ) -> Int {
        guard !groups.isEmpty else { return 0 }
        let selectedGroupID = selectedPresentationGroupIDByFile[fileID]
        if let selectedGroupID,
           let index = groups.firstIndex(where: { $0.id == selectedGroupID }) {
            return index
        }
        return 0
    }

    private func knowledgeLevelCountChips(from document: GNodeDocument) -> [KnowledgeLevelCountChip] {
        var counts: [String: Int] = [:]
        let orderedLevels: [(id: String, title: String)] = [
            ("remember", S("edu.knowledge.type.remember")),
            ("understand", S("edu.knowledge.type.understand")),
            ("apply", S("edu.knowledge.type.apply")),
            ("analyze", S("edu.knowledge.type.analyze")),
            ("evaluate", S("edu.knowledge.type.evaluate")),
            ("create", S("edu.knowledge.type.create"))
        ]

        for node in document.nodes where node.nodeType == EduNodeType.knowledge {
            let rawLevel = node.nodeData["level"] ?? ""
            let canonical = canonicalKnowledgeLevelID(from: rawLevel) ?? "remember"
            counts[canonical, default: 0] += 1
        }

        return orderedLevels.map { level in
            KnowledgeLevelCountChip(
                id: level.id,
                title: level.title,
                count: counts[level.id, default: 0]
            )
        }
    }

    private func defaultKnowledgeLevelCountChips() -> [KnowledgeLevelCountChip] {
        [
            KnowledgeLevelCountChip(id: "remember", title: S("edu.knowledge.type.remember"), count: 0),
            KnowledgeLevelCountChip(id: "understand", title: S("edu.knowledge.type.understand"), count: 0),
            KnowledgeLevelCountChip(id: "apply", title: S("edu.knowledge.type.apply"), count: 0),
            KnowledgeLevelCountChip(id: "analyze", title: S("edu.knowledge.type.analyze"), count: 0),
            KnowledgeLevelCountChip(id: "evaluate", title: S("edu.knowledge.type.evaluate"), count: 0),
            KnowledgeLevelCountChip(id: "create", title: S("edu.knowledge.type.create"), count: 0)
        ]
    }

    private struct BloomLevelChartView: View {
        let chips: [KnowledgeLevelCountChip]
        let isChinese: Bool

        @State private var tooltipIndex: Int? = nil

        private let barColors: [Color] = [
            Color(red: 0.35, green: 0.55, blue: 0.95),
            Color(red: 0.20, green: 0.75, blue: 0.65),
            Color(red: 0.92, green: 0.78, blue: 0.22),
            Color(red: 0.95, green: 0.55, blue: 0.22),
            Color(red: 0.88, green: 0.32, blue: 0.32),
            Color(red: 0.72, green: 0.35, blue: 0.92)
        ]

        var body: some View {
            let pairs = Array(zip(chips, barColors))
            let total = chips.reduce(0) { $0 + $1.count }
            let gap: CGFloat = 2
            let minSegWidth: CGFloat = 6

            VStack(alignment: .leading, spacing: 4) {
                Text(isChinese ? "知识层级" : "Knowledge Hierarchy")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)

                GeometryReader { geo in
                    let totalGaps = gap * CGFloat(pairs.count - 1)
                    let availableWidth = max(geo.size.width - totalGaps, 0)
                    let zeroCount = CGFloat(pairs.filter { $0.0.count == 0 }.count)
                    let reservedForZero = zeroCount * minSegWidth
                    let availableForNonZero = max(availableWidth - reservedForZero, 0)
                    let nonZeroTotal = CGFloat(pairs.filter { $0.0.count > 0 }.reduce(0) { $0 + $1.0.count })
                    let widths: [CGFloat] = pairs.map { chip, _ in
                        if total == 0 { return availableWidth / CGFloat(chips.count) }
                        if chip.count == 0 { return minSegWidth }
                        return nonZeroTotal > 0
                            ? (CGFloat(chip.count) / nonZeroTotal) * availableForNonZero
                            : minSegWidth
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        // Bar: numbers only inside, consistent font size
                        HStack(spacing: gap) {
                            ForEach(Array(pairs.enumerated()), id: \.offset) { i, pair in
                                let (chip, color) = pair
                                let w = widths[i]
                                ZStack {
                                    Rectangle()
                                        .fill(chip.count > 0 ? color : color.opacity(0.15))
                                    if w > 10 {
                                        Text("\(chip.count)")
                                            .font(.system(size: 8, weight: .bold).monospacedDigit())
                                            .foregroundStyle(.white.opacity(chip.count > 0 ? 0.92 : 0.35))
                                    }
                                }
                                .frame(width: w, height: 14)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        tooltipIndex = tooltipIndex == i ? nil : i
                                    }
                                }
                            }
                        }
                        .clipShape(Capsule())

                        // Dot legend row aligned to bar segments
                        HStack(spacing: gap) {
                            ForEach(Array(pairs.enumerated()), id: \.offset) { i, pair in
                                let (_, color) = pair
                                let w = widths[i]
                                Circle()
                                    .fill(chips[i].count > 0 ? color : color.opacity(0.22))
                                    .frame(width: 4, height: 4)
                                    .frame(width: w)
                            }
                        }
                    }
                }
                .frame(height: 21)

                // Tap-to-reveal level name tooltip
                if let idx = tooltipIndex, chips.indices.contains(idx) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(barColors.indices.contains(idx) ? barColors[idx] : .secondary)
                            .frame(width: 5, height: 5)
                        Text(chips[idx].title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(barColors.indices.contains(idx) ? barColors[idx] : .primary)
                        Spacer(minLength: 0)
                        Text("\(chips[idx].count)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
                }
            }
        }
    }

    private func canonicalKnowledgeLevelID(from raw: String) -> String? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        if normalized.contains("remember")
            || normalized.contains("recall")
            || normalized.contains("记忆")
            || normalized.contains("识记")
            || normalized.contains(S("edu.knowledge.type.remember").lowercased()) {
            return "remember"
        }
        if normalized.contains("understand")
            || normalized.contains("理解")
            || normalized.contains(S("edu.knowledge.type.understand").lowercased()) {
            return "understand"
        }
        if normalized.contains("apply")
            || normalized.contains("应用")
            || normalized.contains("实践")
            || normalized.contains(S("edu.knowledge.type.apply").lowercased()) {
            return "apply"
        }
        if normalized.contains("analyze")
            || normalized.contains("analyse")
            || normalized.contains("分析")
            || normalized.contains(S("edu.knowledge.type.analyze").lowercased()) {
            return "analyze"
        }
        if normalized.contains("evaluate")
            || normalized.contains("assessment")
            || normalized.contains("评价")
            || normalized.contains("评估")
            || normalized.contains(S("edu.knowledge.type.evaluate").lowercased()) {
            return "evaluate"
        }
        if normalized.contains("create")
            || normalized.contains("创造")
            || normalized.contains("创作")
            || normalized.contains(S("edu.knowledge.type.create").lowercased()) {
            return "create"
        }
        return nil
    }

    private func reachableEvaluationNodeIDs(
        from startNodeIDs: Set<UUID>,
        outgoingByNode: [UUID: [UUID]],
        nodeTypeByID: [UUID: String]
    ) -> Set<UUID> {
        guard !startNodeIDs.isEmpty else { return [] }

        var queue: [UUID] = Array(startNodeIDs)
        var head = 0
        var visited: Set<UUID> = startNodeIDs
        var evaluationIDs: Set<UUID> = []

        while head < queue.count {
            let current = queue[head]
            head += 1

            if nodeTypeByID[current] == EduNodeType.evaluation {
                evaluationIDs.insert(current)
            }

            for next in outgoingByNode[current] ?? [] {
                guard !visited.contains(next) else { continue }
                visited.insert(next)
                queue.append(next)
            }
        }

        return evaluationIDs
    }

    private func evaluationDescriptor(
        for node: SerializableNode,
        customName: String?
    ) -> EvaluationNodeDescriptor {
        let custom = (customName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = custom.isEmpty ? node.attributes.name : custom
        let textFields = parseJSONStringDictionary(node.nodeData["evaluationTextFields"])
        let indicatorsRaw = textFields["evaluation_indicators"] ?? node.nodeData["evaluation_indicators"] ?? ""
        let indicators = parseEvaluationIndicators(
            from: indicatorsRaw,
            fallbackInputPorts: node.inputPorts
        )
        return EvaluationNodeDescriptor(
            id: node.id,
            title: title,
            indicators: indicators
        )
    }

    private func parseEvaluationIndicators(
        from raw: String,
        fallbackInputPorts: [SerializablePort]
    ) -> [EvaluationIndicatorDescriptor] {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        var descriptors: [EvaluationIndicatorDescriptor] = []

        for line in normalized.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let normalizedLine = trimmed
                .replacingOccurrences(of: "｜", with: "|")
                .replacingOccurrences(of: "：", with: ":")
            var components = normalizedLine
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

            if components.count == 1 && normalizedLine.contains(":") {
                components = normalizedLine
                    .split(separator: ":", omittingEmptySubsequences: false)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            }

            guard let first = components.first else { continue }
            let name = first.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            var typeToken = components.count > 1 ? components[1] : "score"
            if components.count == 2 && typeToken.contains("/") {
                typeToken = typeToken
                    .split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first ?? "score"
            }

            descriptors.append(
                EvaluationIndicatorDescriptor(
                    id: "\(name.lowercased())-\(descriptors.count)",
                    name: name,
                    kind: isCompletionIndicatorType(typeToken) ? .completion : .score
                )
            )
        }

        if descriptors.isEmpty {
            descriptors = fallbackInputPorts.enumerated().map { index, port in
                let title = port.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return EvaluationIndicatorDescriptor(
                    id: "input-\(index)",
                    name: title.isEmpty ? "\(S("edu.evaluation.autoIndicatorPrefix")) \(index + 1)" : title,
                    kind: .score
                )
            }
        }

        return descriptors
    }

    private func isCompletionIndicatorType(_ raw: String) -> Bool {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        let tokens = ["completion", "complete", "done", "binary", "yes/no", "完成", "达成", "完成制"]
        return tokens.contains(where: { normalized.contains($0) })
    }

    private func parseJSONStringDictionary(_ raw: String?) -> [String: String] {
        guard let raw, !raw.isEmpty, let data = raw.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func parsedStudentNames(from studentProfile: String) -> [String] {
        let text: String
        if let extracted = extractedRosterText(from: studentProfile) {
            text = extracted
        } else if studentProfile.contains("|") {
            text = studentProfile
        } else {
            return []
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let textToParse = trimmedText
        guard !textToParse.isEmpty else { return [] }

        let lines = textToParse
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var names: [String] = []

        for line in lines {
            if line.contains("="), !line.contains("|"), !line.contains(",") {
                continue
            }

            let name: String
            if line.contains("|") {
                name = line
                    .split(separator: "|", omittingEmptySubsequences: false)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first ?? ""
            } else if line.contains(",") {
                name = line
                    .split(separator: ",", omittingEmptySubsequences: false)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first ?? ""
            } else {
                name = line
            }

            let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowered = normalizedName.lowercased()
            if normalizedName.isEmpty || lowered == "name" || normalizedName == "姓名" {
                continue
            }
            names.append(normalizedName)
        }

        return deduplicatedStudentNames(names)
    }

    private func extractedRosterText(from studentProfile: String) -> String? {
        let trimmed = studentProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let range = trimmed.range(of: "roster=") else {
            return trimmed.contains("|") ? trimmed : nil
        }

        let start = range.upperBound
        let suffix = trimmed[start...]
        var end = suffix.endIndex
        for marker in [", organization=", ",organization=", ", outputs=", ",outputs="] {
            if let markerRange = suffix.range(of: marker), markerRange.lowerBound < end {
                end = markerRange.lowerBound
            }
        }

        let roster = String(suffix[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return roster.isEmpty ? nil : roster
    }

    private func openStudentRosterEditor(for file: GNodeWorkspaceFile) {
        creationDraft = CourseCreationDraft()
        creationDraft.studentRosterText = extractedRosterText(from: file.studentProfile) ?? ""
        studentRosterEditFileID = file.id
        showingStudentRosterEdit = true
    }

    private func saveStudentRoster(_ newRoster: String) {
        guard let fileID = studentRosterEditFileID,
              let file = workspaceFiles.first(where: { $0.id == fileID }) else {
            showingStudentRosterEdit = false
            return
        }

        let existing = file.studentProfile
        if let rosterRange = existing.range(of: "roster=") {
            let suffix = existing[rosterRange.upperBound...]
            var endIdx = suffix.endIndex
            for marker in [", organization=", ",organization=", ", outputs=", ",outputs="] {
                if let r = suffix.range(of: marker), r.lowerBound < endIdx {
                    endIdx = r.lowerBound
                }
            }
            let trailing = endIdx < suffix.endIndex ? String(suffix[endIdx...]) : ""
            let prefix = String(existing[..<rosterRange.lowerBound])
            file.studentProfile = "\(prefix)roster=\(newRoster)\(trailing)"
        } else if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            file.studentProfile = "roster=\(newRoster)"
        } else {
            file.studentProfile = "\(existing), roster=\(newRoster)"
        }

        file.updatedAt = .now
        try? modelContext.save()
        showingStudentRosterEdit = false
    }

    private func deduplicatedStudentNames(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            if seen.insert(value).inserted {
                result.append(value)
            }
        }
        return result
    }

    @ViewBuilder
    private func presentationFilmstrip(
        fileID: UUID,
        courseName: String,
        deck: EduPresentationDeck,
        groups: [EduPresentationSlideGroup],
        slides: [EduPresentationComposedSlide]
    ) -> some View {
        let storedSelectedID = selectedPresentationGroupIDByFile[fileID]
        let selectedGroupID: UUID? = {
            if groups.contains(where: { $0.id == storedSelectedID }) {
                return storedSelectedID
            }
            return groups.first?.id
        }()
        let stripHeight: CGFloat = presentationFilmstripHeight
        let stripVerticalPadding: CGFloat = 8

        VStack(spacing: 0) {
            Spacer(minLength: 0)

            ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        let isSelected = group.id == selectedGroupID
                        let styleState = presentationStylingState(fileID: fileID, groupID: group.id)
                        let overlays = styleState.overlays
                        let pageStyle = styleState.pageStyle
                        let textTheme = styleState.textTheme
                        ZStack(alignment: .topTrailing) {
                            Button {
                                selectPresentationGroup(fileID: fileID, group: group)
                            } label: {
                                presentationSlideThumbnail(
                                    courseName: courseName,
                                    slide: slides.indices.contains(index) ? slides[index] : nil,
                                    overlays: overlays,
                                    nativeTextOverrides: styleState.nativeTextOverrides,
                                    nativeContentOverrides: styleState.nativeContentOverrides,
                                    nativeLayoutOverrides: styleState.nativeLayoutOverrides,
                                    pageStyle: pageStyle,
                                    textTheme: textTheme,
                                    fallbackGroup: group,
                                    displayIndex: index + 1,
                                    isSelected: isSelected,
                                    onLoaded: {
                                        markPresentationThumbnailLoaded(fileID: fileID, groupID: group.id)
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    removeSlideGroupFromPresentation(fileID: fileID, group: group)
                                } label: {
                                    Label(
                                        "Remove",
                                        systemImage: "trash"
                                    )
                                }
                            }

                            HStack(spacing: 4) {
                                presentationMergeBadgeButton(
                                    systemName: "arrow.left",
                                    isEnabled: group.startIndex > 0
                                ) {
                                    mergeSlideGroupBackward(
                                        fileID: fileID,
                                        group: group,
                                        slideCount: deck.orderedSlides.count
                                    )
                                }

                                presentationMergeBadgeButton(
                                    systemName: "arrow.right",
                                    isEnabled: group.endIndex < deck.orderedSlides.count - 1
                                ) {
                                    mergeSlideGroupForward(
                                        fileID: fileID,
                                        group: group,
                                        slideCount: deck.orderedSlides.count
                                    )
                                }
                            }
                            .padding(7)
                        }
                        .id(group.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, stripVerticalPadding)
                .frame(height: stripHeight, alignment: .center)
            }
            .frame(height: stripHeight, alignment: .center)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(height: 1)
            }
            .onChange(of: selectedGroupID) { _, newID in
                guard let newID else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    scrollProxy.scrollTo(newID, anchor: .center)
                }
            }
            .onAppear {
                if let id = selectedGroupID {
                    scrollProxy.scrollTo(id, anchor: .center)
                }
            }
            } // ScrollViewReader
        }
        .ignoresSafeArea(edges: .bottom)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    @ViewBuilder
    private func presentationStylingFloatingEntryButton(
        fileID: UUID,
        groups: [EduPresentationSlideGroup]
    ) -> some View {
        let storedSelectedID = selectedPresentationGroupIDByFile[fileID]
        let selectedGroupID: UUID? = {
            if groups.contains(where: { $0.id == storedSelectedID }) {
                return storedSelectedID
            }
            return groups.first?.id
        }()

        VStack {
            Spacer(minLength: 0)
            HStack {
                presentationStylingEntryButton(
                    isActive: false
                ) {
                    togglePresentationStylingMode(
                        fileID: fileID,
                        groups: groups,
                        selectedGroupID: selectedGroupID
                    )
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 20)
            .padding(.bottom, presentationFilmstripHeight - 14)
        }
        .ignoresSafeArea(edges: .bottom)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    @ViewBuilder
    private func presentationSlideThumbnail(
        courseName: String,
        slide: EduPresentationComposedSlide?,
        overlays: [PresentationSlideOverlay],
        nativeTextOverrides: [PresentationNativeElement: PresentationTextStyleConfig],
        nativeContentOverrides: [PresentationNativeElement: String],
        nativeLayoutOverrides: [PresentationNativeElement: PresentationNativeLayoutOverride],
        pageStyle: PresentationPageStyle,
        textTheme: PresentationTextTheme,
        fallbackGroup: EduPresentationSlideGroup,
        displayIndex: Int,
        isSelected: Bool,
        onLoaded: @escaping () -> Void
    ) -> some View {
        let thumbnailWidth: CGFloat = 286
        let thumbnailHeight: CGFloat = thumbnailWidth / max(0.7, pageStyle.aspectPreset.ratio)
        let title = slide?.title ?? fallbackGroup.slideTitle

        ZStack(alignment: .topLeading) {
            if let slide {
                PresentationSlideThumbnailHTMLView(
                    html: presentationSlideThumbnailHTML(
                        courseName: courseName,
                        slide: slide,
                        overlays: overlays,
                        nativeTextOverrides: nativeTextOverrides,
                        nativeContentOverrides: nativeContentOverrides,
                        nativeLayoutOverrides: nativeLayoutOverrides,
                        pageStyle: pageStyle,
                        textTheme: textTheme
                    ),
                    onLoaded: onLoaded
                )
                .allowsHitTesting(false)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.black)
                        .lineLimit(2)
                    Text(fallbackGroup.subtitle)
                        .font(.system(size: 8, weight: .regular))
                        .foregroundStyle(.black.opacity(0.75))
                        .lineLimit(1)
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(hex: pageStyle.backgroundColorHex))
                .onAppear {
                    onLoaded()
                }
            }

            Text("\(displayIndex)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.75))
                )
                .padding(7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: thumbnailWidth, height: thumbnailHeight, alignment: .leading)
        .background(Color(hex: pageStyle.backgroundColorHex))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Color.cyan : Color.black.opacity(0.1), lineWidth: isSelected ? 2.6 : 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    private func presentationSlideThumbnailHTML(
        courseName: String,
        slide: EduPresentationComposedSlide,
        overlays: [PresentationSlideOverlay],
        nativeTextOverrides: [PresentationNativeElement: PresentationTextStyleConfig],
        nativeContentOverrides: [PresentationNativeElement: String],
        nativeLayoutOverrides: [PresentationNativeElement: PresentationNativeLayoutOverride],
        pageStyle: PresentationPageStyle,
        textTheme: PresentationTextTheme
    ) -> String {
        let baseHTML = themedPresentationSlideHTML(
            courseName: courseName,
            slide: slide,
            isChinese: isChineseUI(),
            pageStyle: pageStyle,
            textTheme: textTheme,
            nativeTextOverrides: nativeTextOverrides,
            nativeContentOverrides: nativeContentOverrides,
            nativeLayoutOverrides: nativeLayoutOverrides
        )
        let slideAspect = max(0.75, pageStyle.aspectPreset.ratio)
        let overlayNodesHTML = presentationOverlayLayerHTML(
            overlays: overlays,
            slideAspect: slideAspect,
            textTheme: textTheme
        )
        guard !overlayNodesHTML.isEmpty else { return baseHTML }

        let layerHTML = "<div class=\"edunode-overlay-layer\">\(overlayNodesHTML)</div>"
        guard let insertion = baseHTML.range(of: "</article>", options: .backwards) else {
            return baseHTML
        }
        return baseHTML.replacingCharacters(
            in: insertion.lowerBound..<insertion.lowerBound,
            with: layerHTML
        )
    }

    @ViewBuilder
    private func presentationMergeBadgeButton(
        systemName: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.55))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(isEnabled ? 0.75 : 0.45))
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func editorExportActions(for file: GNodeWorkspaceFile) -> [NodeEditorExportAction] {
        let context = EduLessonPlanContext(file: file)
        let baseName = sanitizedExportBaseName(file.name)

        return [
            NodeEditorExportAction(
                id: "edunode.courseware",
                title: S("app.export.courseware"),
                systemImage: "rectangle.on.rectangle",
                defaultFilename: "",
                contentType: .data,
                buildData: { graphData in
                    openPresentationPreview(for: file, graphData: graphData)
                    return nil
                }
            ),
            NodeEditorExportAction(
                id: "edunode.lesson.preview",
                title: S("app.export.lessonPlan"),
                systemImage: "doc.text.magnifyingglass",
                defaultFilename: "",
                contentType: .plainText,
                buildData: { graphData in
                    let renderedHTML = EduLessonPlanExporter.html(
                        context: context,
                        graphData: graphData
                    )
                    lessonPlanPreviewPayload = EduLessonPlanPreviewPayload(
                        context: context,
                        graphData: graphData,
                        html: renderedHTML,
                        baseFileName: baseName
                    )
                    return nil
                }
            )
        ]
    }

    private func sanitizedExportBaseName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = S("app.files.defaultName").contains("%d")
            ? String(format: S("app.files.defaultName"), 1)
            : "Course"
        let source = trimmed.isEmpty ? fallback : trimmed
        let sanitized = source
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Course" : sanitized
    }

    private func S(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    private func emptyDocumentData() -> Data {
        let document = GNodeDocument(nodes: [], connections: [], canvasState: [])
        return (try? encodeDocument(document)) ?? Data()
    }
}

#if canImport(UIKit) && canImport(WebKit)
private struct PresentationSlideThumbnailHTMLView: UIViewRepresentable {
    let html: String
    let onLoaded: () -> Void

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: PresentationSlideThumbnailHTMLView
        var lastHTML = ""
        var hasReportedLoadForCurrentHTML = false

        init(parent: PresentationSlideThumbnailHTMLView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            reportLoadedIfNeeded()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            reportLoadedIfNeeded()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            reportLoadedIfNeeded()
        }

        private func reportLoadedIfNeeded() {
            guard !hasReportedLoadForCurrentHTML else { return }
            hasReportedLoadForCurrentHTML = true
            DispatchQueue.main.async {
                self.parent.onLoaded()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = false
        context.coordinator.lastHTML = html
        context.coordinator.hasReportedLoadForCurrentHTML = false
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        context.coordinator.hasReportedLoadForCurrentHTML = false
        uiView.loadHTMLString(html, baseURL: nil)
    }
}
#else
private struct PresentationSlideThumbnailHTMLView: View {
    let html: String
    let onLoaded: () -> Void

    var body: some View {
        Color.white.overlay(
            Text(html)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.black)
                .lineLimit(8)
                .padding(8),
            alignment: .topLeading
        )
        .onAppear {
            onLoaded()
        }
    }
}
#endif

private struct PresentationPersistedState: Codable {
    var version: Int = 1
    var breaks: [Int]
    var excludedNodeIDs: [UUID]
    var selectedGroupID: UUID?
    var selectedGroupSignature: String?
    var pageStyle: PresentationPageStyle
    var textTheme: PresentationTextTheme
    var updatedAt: Date?
    var groups: [PresentationPersistedGroupState]
}

private struct PresentationPersistedGroupState: Codable {
    var groupID: UUID
    var groupSignature: String?
    var selectedOverlayID: UUID?
    var vectorization: PresentationVectorizationSettings
    var nativeTextOverrides: [String: PresentationTextStyleConfig]
    var nativeContentOverrides: [String: String]
    var nativeLayoutOverrides: [String: PresentationNativeLayoutOverride]
    var overlays: [PresentationPersistedOverlay]

    init(
        groupID: UUID,
        groupSignature: String?,
        selectedOverlayID: UUID?,
        vectorization: PresentationVectorizationSettings,
        nativeTextOverrides: [String: PresentationTextStyleConfig] = [:],
        nativeContentOverrides: [String: String] = [:],
        nativeLayoutOverrides: [String: PresentationNativeLayoutOverride] = [:],
        overlays: [PresentationPersistedOverlay]
    ) {
        self.groupID = groupID
        self.groupSignature = groupSignature
        self.selectedOverlayID = selectedOverlayID
        self.vectorization = vectorization
        self.nativeTextOverrides = nativeTextOverrides
        self.nativeContentOverrides = nativeContentOverrides
        self.nativeLayoutOverrides = nativeLayoutOverrides
        self.overlays = overlays
    }

    private enum CodingKeys: String, CodingKey {
        case groupID
        case groupSignature
        case selectedOverlayID
        case vectorization
        case nativeTextOverrides
        case nativeContentOverrides
        case nativeLayoutOverrides
        case overlays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groupID = try container.decode(UUID.self, forKey: .groupID)
        groupSignature = try? container.decode(String.self, forKey: .groupSignature)
        selectedOverlayID = try? container.decode(UUID.self, forKey: .selectedOverlayID)
        vectorization = (try? container.decode(PresentationVectorizationSettings.self, forKey: .vectorization)) ?? .default
        nativeTextOverrides = (try? container.decode([String: PresentationTextStyleConfig].self, forKey: .nativeTextOverrides)) ?? [:]
        nativeContentOverrides = (try? container.decode([String: String].self, forKey: .nativeContentOverrides)) ?? [:]
        nativeLayoutOverrides = (try? container.decode([String: PresentationNativeLayoutOverride].self, forKey: .nativeLayoutOverrides)) ?? [:]
        overlays = (try? container.decode([PresentationPersistedOverlay].self, forKey: .overlays)) ?? []
    }
}

private struct PresentationPersistedOverlay: Codable {
    var id: UUID
    var kindRaw: String
    var imageData: Data
    var extractedImageData: Data?
    var cropSourceImageData: Data?
    var cropOriginX: Double
    var cropOriginY: Double
    var cropWidth: Double
    var cropHeight: Double
    var vectorDocument: PresentationPersistedSVGDocument?
    var selectedFilterRaw: String
    var stylization: PresentationPersistedStylization
    var centerX: Double
    var centerY: Double
    var normalizedWidth: Double
    var normalizedHeight: Double
    var aspectRatio: Double
    var rotationDegrees: Double
    var textContent: String
    var textStylePreset: PresentationTextStylePreset
    var textColorHex: String
    var textAlignment: PresentationTextAlignment
    var textFontSize: Double
    var textWeightValue: Double
    var shapeFillColorHex: String
    var shapeBorderColorHex: String
    var shapeBorderWidth: Double
    var shapeCornerRadiusRatio: Double
    var shapeStyleRaw: String
    var iconSystemName: String
    var iconColorHex: String
    var iconHasBackground: Bool
    var iconBackgroundColorHex: String
    var imageCornerRadiusRatio: Double
    var vectorStrokeColorHex: String
    var vectorBackgroundColorHex: String
    var vectorBackgroundVisible: Bool

    init(
        id: UUID,
        kindRaw: String,
        imageData: Data,
        extractedImageData: Data?,
        cropSourceImageData: Data?,
        cropOriginX: Double,
        cropOriginY: Double,
        cropWidth: Double,
        cropHeight: Double,
        vectorDocument: PresentationPersistedSVGDocument?,
        selectedFilterRaw: String,
        stylization: PresentationPersistedStylization,
        centerX: Double,
        centerY: Double,
        normalizedWidth: Double,
        normalizedHeight: Double,
        aspectRatio: Double,
        rotationDegrees: Double,
        textContent: String,
        textStylePreset: PresentationTextStylePreset,
        textColorHex: String,
        textAlignment: PresentationTextAlignment,
        textFontSize: Double,
        textWeightValue: Double,
        shapeFillColorHex: String,
        shapeBorderColorHex: String,
        shapeBorderWidth: Double,
        shapeCornerRadiusRatio: Double,
        shapeStyleRaw: String,
        iconSystemName: String,
        iconColorHex: String,
        iconHasBackground: Bool,
        iconBackgroundColorHex: String,
        imageCornerRadiusRatio: Double,
        vectorStrokeColorHex: String,
        vectorBackgroundColorHex: String,
        vectorBackgroundVisible: Bool
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.imageData = imageData
        self.extractedImageData = extractedImageData
        self.cropSourceImageData = cropSourceImageData
        self.cropOriginX = cropOriginX
        self.cropOriginY = cropOriginY
        self.cropWidth = cropWidth
        self.cropHeight = cropHeight
        self.vectorDocument = vectorDocument
        self.selectedFilterRaw = selectedFilterRaw
        self.stylization = stylization
        self.centerX = centerX
        self.centerY = centerY
        self.normalizedWidth = normalizedWidth
        self.normalizedHeight = normalizedHeight
        self.aspectRatio = aspectRatio
        self.rotationDegrees = rotationDegrees
        self.textContent = textContent
        self.textStylePreset = textStylePreset
        self.textColorHex = textColorHex
        self.textAlignment = textAlignment
        self.textFontSize = textFontSize
        self.textWeightValue = textWeightValue
        self.shapeFillColorHex = shapeFillColorHex
        self.shapeBorderColorHex = shapeBorderColorHex
        self.shapeBorderWidth = shapeBorderWidth
        self.shapeCornerRadiusRatio = shapeCornerRadiusRatio
        self.shapeStyleRaw = shapeStyleRaw
        self.iconSystemName = iconSystemName
        self.iconColorHex = iconColorHex
        self.iconHasBackground = iconHasBackground
        self.iconBackgroundColorHex = iconBackgroundColorHex
        self.imageCornerRadiusRatio = imageCornerRadiusRatio
        self.vectorStrokeColorHex = vectorStrokeColorHex
        self.vectorBackgroundColorHex = vectorBackgroundColorHex
        self.vectorBackgroundVisible = vectorBackgroundVisible
    }

    private enum CodingKeys: String, CodingKey {
        case id, kindRaw, imageData, extractedImageData, cropSourceImageData, cropOriginX, cropOriginY, cropWidth, cropHeight, vectorDocument, selectedFilterRaw, stylization
        case centerX, centerY, normalizedWidth, normalizedHeight, aspectRatio, rotationDegrees
        case textContent, textStylePreset, textColorHex, textAlignment, textFontSize, textWeightValue
        case shapeFillColorHex, shapeBorderColorHex, shapeBorderWidth, shapeCornerRadiusRatio, shapeStyleRaw
        case iconSystemName, iconColorHex, iconHasBackground, iconBackgroundColorHex
        case imageCornerRadiusRatio
        case vectorStrokeColorHex, vectorBackgroundColorHex, vectorBackgroundVisible
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kindRaw = try container.decode(String.self, forKey: .kindRaw)
        imageData = (try? container.decode(Data.self, forKey: .imageData)) ?? Data()
        extractedImageData = try? container.decode(Data.self, forKey: .extractedImageData)
        cropSourceImageData = try? container.decode(Data.self, forKey: .cropSourceImageData)
        cropOriginX = (try? container.decode(Double.self, forKey: .cropOriginX)) ?? 0
        cropOriginY = (try? container.decode(Double.self, forKey: .cropOriginY)) ?? 0
        cropWidth = (try? container.decode(Double.self, forKey: .cropWidth)) ?? 1
        cropHeight = (try? container.decode(Double.self, forKey: .cropHeight)) ?? 1
        vectorDocument = try? container.decode(PresentationPersistedSVGDocument.self, forKey: .vectorDocument)
        selectedFilterRaw = (try? container.decode(String.self, forKey: .selectedFilterRaw)) ?? SVGFilterStyle.original.rawValue
        stylization = (try? container.decode(PresentationPersistedStylization.self, forKey: .stylization))
            ?? PresentationPersistedStylization(from: .default)
        centerX = (try? container.decode(Double.self, forKey: .centerX)) ?? 0.5
        centerY = (try? container.decode(Double.self, forKey: .centerY)) ?? 0.58
        normalizedWidth = (try? container.decode(Double.self, forKey: .normalizedWidth)) ?? 0.28
        normalizedHeight = (try? container.decode(Double.self, forKey: .normalizedHeight)) ?? 0.2
        aspectRatio = (try? container.decode(Double.self, forKey: .aspectRatio)) ?? 1
        rotationDegrees = (try? container.decode(Double.self, forKey: .rotationDegrees)) ?? 0
        textContent = (try? container.decode(String.self, forKey: .textContent)) ?? ""
        textStylePreset = (try? container.decode(PresentationTextStylePreset.self, forKey: .textStylePreset)) ?? .paragraph
        textColorHex = (try? container.decode(String.self, forKey: .textColorHex)) ?? "#111111"
        textAlignment = (try? container.decode(PresentationTextAlignment.self, forKey: .textAlignment)) ?? .leading
        textFontSize = (try? container.decode(Double.self, forKey: .textFontSize)) ?? 24
        textWeightValue = (try? container.decode(Double.self, forKey: .textWeightValue)) ?? 0.5
        shapeFillColorHex = (try? container.decode(String.self, forKey: .shapeFillColorHex)) ?? "#FFFFFF"
        shapeBorderColorHex = (try? container.decode(String.self, forKey: .shapeBorderColorHex)) ?? "#D6DDE8"
        shapeBorderWidth = (try? container.decode(Double.self, forKey: .shapeBorderWidth)) ?? 1.2
        shapeCornerRadiusRatio = (try? container.decode(Double.self, forKey: .shapeCornerRadiusRatio)) ?? 0.18
        shapeStyleRaw = (try? container.decode(String.self, forKey: .shapeStyleRaw)) ?? PresentationShapeStyle.roundedRect.rawValue
        iconSystemName = (try? container.decode(String.self, forKey: .iconSystemName)) ?? "wrench.adjustable"
        iconColorHex = (try? container.decode(String.self, forKey: .iconColorHex)) ?? "#111111"
        iconHasBackground = (try? container.decode(Bool.self, forKey: .iconHasBackground)) ?? true
        iconBackgroundColorHex = (try? container.decode(String.self, forKey: .iconBackgroundColorHex)) ?? "#FFFFFF"
        imageCornerRadiusRatio = (try? container.decode(Double.self, forKey: .imageCornerRadiusRatio)) ?? 0
        vectorStrokeColorHex = (try? container.decode(String.self, forKey: .vectorStrokeColorHex)) ?? "#0F172A"
        vectorBackgroundColorHex = (try? container.decode(String.self, forKey: .vectorBackgroundColorHex)) ?? "#FFFFFF"
        vectorBackgroundVisible = (try? container.decode(Bool.self, forKey: .vectorBackgroundVisible)) ?? false
    }
}

private struct PresentationPersistedSVGDocument: Codable {
    var width: Int
    var height: Int
    var body: String
}

private struct PresentationPersistedStylization: Codable {
    var flowDisplacement: Double
    var flowOctaves: Double
    var crayonRoughness: Double
    var crayonWax: Double
    var crayonHatchDensity: Double
    var pixelDotSize: Double
    var pixelDensity: Double
    var pixelJitter: Double
    var equationN: Double
    var equationTheta: Double
    var equationScale: Double
    var equationContrast: Double

    init(from source: SVGStylizationParameters) {
        flowDisplacement = source.flowDisplacement
        flowOctaves = source.flowOctaves
        crayonRoughness = source.crayonRoughness
        crayonWax = source.crayonWax
        crayonHatchDensity = source.crayonHatchDensity
        pixelDotSize = source.pixelDotSize
        pixelDensity = source.pixelDensity
        pixelJitter = source.pixelJitter
        equationN = source.equationN
        equationTheta = source.equationTheta
        equationScale = source.equationScale
        equationContrast = source.equationContrast
    }

    var value: SVGStylizationParameters {
        SVGStylizationParameters(
            flowDisplacement: flowDisplacement,
            flowOctaves: flowOctaves,
            crayonRoughness: crayonRoughness,
            crayonWax: crayonWax,
            crayonHatchDensity: crayonHatchDensity,
            pixelDotSize: pixelDotSize,
            pixelDensity: pixelDensity,
            pixelJitter: pixelJitter,
            equationN: equationN,
            equationTheta: equationTheta,
            equationScale: equationScale,
            equationContrast: equationContrast
        )
    }
}

private struct AnimatedGradientRing: View {
    let lineWidth: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let rotation = Angle.degrees(
                (timeline.date.timeIntervalSinceReferenceDate * 72.0)
                    .truncatingRemainder(dividingBy: 360)
            )
            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(
                            colors: [
                                Color(red: 0.99, green: 0.37, blue: 0.54),
                                Color(red: 0.99, green: 0.70, blue: 0.26),
                                Color(red: 0.28, green: 0.89, blue: 0.70),
                                Color(red: 0.27, green: 0.67, blue: 0.98),
                                Color(red: 0.72, green: 0.49, blue: 0.98),
                                Color(red: 0.99, green: 0.37, blue: 0.54)
                            ]
                        ),
                        center: .center,
                        angle: rotation
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
        }
        .padding(1)
    }
}

private struct AnimatedGradientScreenBorder: View {
    let lineWidth: CGFloat
    let inset: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let corner = max(20, min(proxy.size.width, proxy.size.height) * 0.035)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let rotation = Angle.degrees(
                    (timeline.date.timeIntervalSinceReferenceDate * 58.0)
                        .truncatingRemainder(dividingBy: 360)
                )
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(
                                colors: [
                                    Color(red: 0.99, green: 0.35, blue: 0.53),
                                    Color(red: 1.00, green: 0.76, blue: 0.25),
                                    Color(red: 0.28, green: 0.88, blue: 0.72),
                                    Color(red: 0.25, green: 0.66, blue: 0.98),
                                    Color(red: 0.74, green: 0.50, blue: 0.99),
                                    Color(red: 0.99, green: 0.35, blue: 0.53)
                                ]
                            ),
                            center: .center,
                            angle: rotation
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                    )
                    .padding(inset)
            }
        }
    }
}

private extension Color {
    init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        if cleaned.count == 3 {
            cleaned = cleaned.map { "\($0)\($0)" }.joined()
        }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            self = Color.white
            return
        }
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}

#Preview {
    ContentView()
}
