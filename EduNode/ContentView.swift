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

@MainActor
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GNodeWorkspaceFile.createdAt, order: .forward) private var workspaceFiles: [GNodeWorkspaceFile]
    @AppStorage("edunode.seeded_default_course.v1") private var didSeedDefaultCourse = false

    @State private var selectedFileID: UUID?
    @State private var splitVisibility: NavigationSplitViewVisibility = .automatic
    @State private var showingCreateCourseSheet = false
    @State private var creationDraft = CourseCreationDraft()
    @State private var showingDocs = false
    @State private var showingSidebarImporter = false
    @State private var lessonPlanPreviewPayload: EduLessonPlanPreviewPayload?
    @State private var presentationPreviewPayload: EduPresentationPreviewPayload?
    @State private var showingPresentationEmptyAlert = false
    @State private var activePresentationModeFileID: UUID?
    @State private var presentationBreaksByFile: [UUID: Set<Int>] = [:]
    @State private var selectedPresentationGroupIDByFile: [UUID: UUID] = [:]
    @State private var cameraRequest: NodeEditorCameraRequest?
    @State private var pendingFlowStepConfirmation: EduFlowStep?
    @State private var pendingFlowStepFileID: UUID?
    @State private var pendingFlowStepIsDone = false
    @State private var isSidebarBasicInfoExpanded = false
    @State private var editorStatsByFileID: [UUID: NodeEditorCanvasStats] = [:]

    private let modelRules = EduPlanning.loadModelRules()
    private var eduNodeMenuSections: [NodeMenuSectionConfig] {
        GNodeNodeKit.gnodeNodeKit.canvasMenuSections()
    }

    // When sidebar is hidden, reserve space for the system's circular sidebar reveal button.
    private var topToolbarLeadingReservedWidth: CGFloat {
        splitVisibility == .detailOnly ? 52 : 0
    }

    var body: some View {
        GeometryReader { rootGeometry in
            NavigationSplitView(columnVisibility: $splitVisibility) {
                sidebarView
            } detail: {
                if showingCreateCourseSheet {
                    Color(white: 0.1)
                        .ignoresSafeArea()
                } else {
                    let topToolbarPadding = rootGeometry.safeAreaInsets.top + (splitVisibility == .detailOnly ? 0 : 8)
                    detailView(
                        toolbarTopPadding: topToolbarPadding,
                        bottomSafeInset: rootGeometry.safeAreaInsets.bottom
                    )
                }
            }
            .navigationSplitViewStyle(.balanced)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            seedDefaultCourseIfNeeded()
            syncSelectedWorkspaceFile()
            migrateWorkspaceFilesIfNeeded()
        }
        .onChange(of: workspaceFiles.map(\.id)) { _, _ in
            syncSelectedWorkspaceFile()
            migrateWorkspaceFilesIfNeeded()
            if let activePresentationModeFileID,
               !workspaceFiles.contains(where: { $0.id == activePresentationModeFileID }) {
                self.activePresentationModeFileID = nil
            }
            let existingIDs = Set(workspaceFiles.map(\.id))
            selectedPresentationGroupIDByFile = selectedPresentationGroupIDByFile.filter { existingIDs.contains($0.key) }
        }
        .onChange(of: selectedFileID) { _, _ in
            isSidebarBasicInfoExpanded = false
        }
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
        .sheet(item: $lessonPlanPreviewPayload) { payload in
            EduLessonPlanPreviewSheet(payload: payload)
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
    private func detailView(toolbarTopPadding: CGFloat, bottomSafeInset: CGFloat) -> some View {
        if let file = selectedWorkspaceFile {
            let deck = EduPresentationPlanner.makeDeck(graphData: file.data)
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
                    topCenterOverlay: AnyView(
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
                    onDocumentDataChange: { data in
                        persistWorkspaceFileData(id: file.id, data: data)
                    }
                )
                .id(file.id)
                .ignoresSafeArea(edges: [.top, .bottom])
                .toolbarBackground(.hidden, for: .navigationBar)

                if isPresentationModeActive && !slideGroups.isEmpty {
                    presentationFilmstrip(
                        fileID: file.id,
                        deck: deck,
                        groups: slideGroups,
                        slides: composedSlides
                    )
                    .zIndex(2000)
                }

                editorStatsOverlay(
                    stats: statsForDisplay(for: file),
                    bottomSafeInset: bottomSafeInset
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
            NodeDocumentationView(onClose: {
                showingDocs = false
            })
        } else {
            Text(S("app.docs.unsupported"))
                .padding()
        }
    }

    private var selectedWorkspaceFile: GNodeWorkspaceFile? {
        if let selectedFileID {
            return workspaceFiles.first(where: { $0.id == selectedFileID })
        }
        return workspaceFiles.first
    }

    private func presentCreateCourseSheet() {
        creationDraft = CourseCreationDraft()
        showingCreateCourseSheet = true
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
            modelID: "inquiry",
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

    private func deleteWorkspaceFile(_ file: GNodeWorkspaceFile) {
        let currentID = file.id
        let orderedIDs = workspaceFiles.map(\.id)
        let currentIndex = orderedIDs.firstIndex(of: currentID) ?? 0
        let remainingIDs = orderedIDs.filter { $0 != currentID }

        modelContext.delete(file)
        try? modelContext.save()

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
        let roles = EduPlanning.roles(in: file.data)

        let basicInfoDone = isBasicInfoComplete(file)
        let modelDone = !file.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let knowledgeToolkitDone = file.knowledgeToolkitMarkedDone
        let evaluationDesignDone = roles.contains("evaluation_metric")
            && roles.contains("evaluation_summary")

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
        let roles = EduPlanning.roles(in: file.data)
        let knowledgeToolkitDone = file.knowledgeToolkitMarkedDone
        let evaluationDesignDone = roles.contains("evaluation_metric")
            && roles.contains("evaluation_summary")

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
    private func editorStatsOverlay(stats: NodeEditorCanvasStats, bottomSafeInset: CGFloat) -> some View {
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
            .padding(.bottom, max(bottomSafeInset, 12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .allowsHitTesting(false)
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
        let isActive = activePresentationModeFileID == file.id
        return [
            NodeEditorToolbarAction(
                id: "edunode.present",
                title: isActive ? S("app.presentation.exit") : S("app.presentation.button"),
                systemImage: isActive ? "xmark.rectangle.portrait" : "play.rectangle.on.rectangle",
                accent: .orange,
                minWidth: 102
            ) {
                togglePresentationMode(for: file)
            }
        ]
    }

    private func togglePresentationMode(for file: GNodeWorkspaceFile) {
        if activePresentationModeFileID == file.id {
            activePresentationModeFileID = nil
            return
        }

        let deck = EduPresentationPlanner.makeDeck(graphData: file.data)
        guard !deck.orderedSlides.isEmpty else {
            showingPresentationEmptyAlert = true
            return
        }

        activePresentationModeFileID = file.id
        if let firstGroup = presentationGroups(for: file.id, deck: deck).first {
            selectedPresentationGroupIDByFile[file.id] = firstGroup.id
            focusOnSlideGroup(firstGroup)
        }
    }

    private func openPresentationPreview(for file: GNodeWorkspaceFile, graphData: Data? = nil) {
        let sourceData = graphData ?? file.data
        let deck = EduPresentationPlanner.makeDeck(graphData: sourceData)
        guard !deck.orderedSlides.isEmpty else {
            showingPresentationEmptyAlert = true
            return
        }
        let groups = presentationGroups(for: file.id, deck: deck)
        let slides = EduPresentationPlanner.composeSlides(
            from: groups,
            isChinese: isChineseUI()
        )
        presentationPreviewPayload = EduPresentationPreviewPayload(
            courseName: file.name,
            baseFileName: sanitizedExportBaseName(file.name),
            slides: slides
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

    private func mergeSlideGroupBackward(fileID: UUID, group: EduPresentationSlideGroup, slideCount: Int) {
        guard group.startIndex > 0 else { return }
        var breaks = effectivePresentationBreaks(fileID: fileID, slideCount: slideCount)
        breaks.remove(group.startIndex - 1)
        presentationBreaksByFile[fileID] = breaks
    }

    private func mergeSlideGroupForward(fileID: UUID, group: EduPresentationSlideGroup, slideCount: Int) {
        guard group.endIndex < slideCount - 1 else { return }
        var breaks = effectivePresentationBreaks(fileID: fileID, slideCount: slideCount)
        breaks.remove(group.endIndex)
        presentationBreaksByFile[fileID] = breaks
    }

    private func focusOnSlideGroup(_ group: EduPresentationSlideGroup) {
        cameraRequest = NodeEditorCameraRequest(canvasPosition: group.anchorPosition)
    }

    @ViewBuilder
    private func presentationFilmstrip(
        fileID: UUID,
        deck: EduPresentationDeck,
        groups: [EduPresentationSlideGroup],
        slides: [EduPresentationComposedSlide]
    ) -> some View {
        let storedSelectedID = selectedPresentationGroupIDByFile[fileID]
        let selectedGroupID = groups.contains(where: { $0.id == storedSelectedID }) ? storedSelectedID : groups.first?.id

        VStack {
            Spacer(minLength: 0)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        let isSelected = group.id == selectedGroupID
                        ZStack(alignment: .topTrailing) {
                            presentationSlideThumbnail(
                                slide: slides.indices.contains(index) ? slides[index] : nil,
                                fallbackGroup: group,
                                displayIndex: index + 1,
                                isSelected: isSelected
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .onTapGesture {
                                selectedPresentationGroupIDByFile[fileID] = group.id
                                focusOnSlideGroup(group)
                            }

                            HStack(spacing: 4) {
                                Button {
                                    mergeSlideGroupBackward(
                                        fileID: fileID,
                                        group: group,
                                        slideCount: deck.orderedSlides.count
                                    )
                                } label: {
                                    Image(systemName: "arrow.left.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(group.startIndex > 0 ? Color.primary : Color.secondary.opacity(0.35))
                                }
                                .buttonStyle(.plain)
                                .disabled(group.startIndex == 0)

                                Button {
                                    mergeSlideGroupForward(
                                        fileID: fileID,
                                        group: group,
                                        slideCount: deck.orderedSlides.count
                                    )
                                } label: {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(group.endIndex < deck.orderedSlides.count - 1 ? Color.primary : Color.secondary.opacity(0.35))
                                }
                                .buttonStyle(.plain)
                                .disabled(group.endIndex >= deck.orderedSlides.count - 1)
                            }
                            .padding(.top, 6)
                            .padding(.trailing, 6)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(height: 1)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    @ViewBuilder
    private func presentationSlideThumbnail(
        slide: EduPresentationComposedSlide?,
        fallbackGroup: EduPresentationSlideGroup,
        displayIndex: Int,
        isSelected: Bool
    ) -> some View {
        let thumbnailWidth: CGFloat = 250
        let thumbnailHeight: CGFloat = thumbnailWidth * 9.0 / 16.0
        let title = slide?.title ?? fallbackGroup.slideTitle

        ZStack(alignment: .topLeading) {
            if let slide {
                PresentationSlideThumbnailHTMLView(
                    html: EduPresentationHTMLExporter.singleSlideHTML(
                        courseName: title,
                        slide: slide,
                        isChinese: isChineseUI()
                    )
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
                .background(Color.white)
            }

            Text("P\(displayIndex)")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.75))
                )
                .padding(6)
        }
        .frame(width: thumbnailWidth, height: thumbnailHeight, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Color.cyan : Color.black.opacity(0.1), lineWidth: isSelected ? 2.6 : 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
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

    final class Coordinator {
        var lastHTML = ""
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = false
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        uiView.loadHTMLString(html, baseURL: nil)
    }
}
#else
private struct PresentationSlideThumbnailHTMLView: View {
    let html: String

    var body: some View {
        Color.white.overlay(
            Text(html)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.black)
                .lineLimit(8)
                .padding(8),
            alignment: .topLeading
        )
    }
}
#endif

#Preview {
    ContentView()
}
