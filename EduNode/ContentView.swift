//
//  ContentView.swift
//  EduNode
//
//  Created by Euan on 2/15/26.
//

import SwiftUI
import SwiftData
import GNodeKit

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
    @State private var isCourseContextExpanded = true

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
        .fullScreenCover(isPresented: $showingDocs) {
            docsContent
                .ignoresSafeArea()
        }
    }

    private var sidebarView: some View {
        List(selection: $selectedFileID) {
            ForEach(workspaceFiles, id: \.id) { file in
                HStack(spacing: 10) {
                    Image(systemName: selectedFileID == file.id ? "doc.text.fill" : "doc.text")
                        .foregroundStyle(selectedFileID == file.id ? .cyan : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .lineLimit(1)
                        Text(fileSubtitle(file))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
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
            }
        }
    }

    @ViewBuilder
    private func detailView(toolbarTopPadding: CGFloat, bottomSafeInset: CGFloat) -> some View {
        if let file = selectedWorkspaceFile {
            ZStack {
                NodeEditorView(
                    documentID: file.id,
                    documentData: file.data,
                    toolbarLeadingPadding: 20 + topToolbarLeadingReservedWidth,
                    toolbarTrailingPadding: 20,
                    toolbarTopPadding: toolbarTopPadding,
                    customNodeMenuSections: eduNodeMenuSections,
                    topCenterOverlay: AnyView(
                        EduFlowProgressView(
                            states: flowStates(for: file),
                            onToggleManual: { step in
                                toggleManualStep(step, for: file)
                            }
                        )
                        .padding(.trailing, 6)
                    ),
                    onDocumentDataChange: { data in
                        persistWorkspaceFileData(id: file.id, data: data)
                    }
                )
                .id(file.id)
                .ignoresSafeArea(edges: [.top, .bottom])
                .toolbarBackground(.hidden, for: .navigationBar)

                HStack {
                    Spacer(minLength: 0)
                    courseContextPanel(for: file)
                }
                .padding(.trailing, 20)
                .padding(.bottom, max(bottomSafeInset, 12) + 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .zIndex(2000)
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
        let name = isChinese ? "珠海观鸟案例" : "Zhuhai Bird Study"
        let subject = isChinese ? "语文" : "Language Arts"
        let goals = isChinese
            ? """
理解珠海气候与鸟类栖息关系
掌握留鸟与候鸟分类
巩固常见鸟类读音与观察表达
"""
            : """
Understand climate-habitat relationships in Zhuhai
Differentiate resident and migratory birds
Practice pronunciation and observation expression
"""

        let file = GNodeWorkspaceFile(
            name: name,
            data: EduPlanning.makeZhuhaiBirdSampleDocumentData(isChinese: isChinese),
            gradeLevel: "grade 4-6",
            gradeMode: "grade",
            gradeMin: 4,
            gradeMax: 6,
            subject: subject,
            lessonDurationMinutes: 45,
            allowOvertime: false,
            periodRange: "",
            studentCount: 32,
            studentProfile: "",
            studentPriorKnowledgeLevel: "70",
            studentMotivationLevel: "75",
            studentSupportNotes: "",
            goalsText: goals,
            modelID: "inquiry",
            teacherTeam: "",
            leadTeacherCount: 1,
            assistantTeacherCount: 0,
            teacherRolePlan: "",
            learningScenario: "",
            curriculumStandard: "",
            resourceConstraints: "",
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
            guard let migratedData = EduPlanning.migrateLegacyKnowledgeInputsAndSampleConnectionsIfNeeded(data: file.data),
                  migratedData != file.data else {
                continue
            }
            file.data = migratedData
            file.updatedAt = .now
            didChange = true
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

    private func flowStates(for file: GNodeWorkspaceFile) -> [EduFlowStepState] {
        let roles = EduPlanning.roles(in: file.data)

        let basicInfoDone = isBasicInfoComplete(file)
        let modelDone = !file.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasKnowledge = EduPlanning.filledNodeCount(of: EduNodeType.knowledge, in: file.data) >= 1
        let hasToolkit = EduPlanning.filledNodeCount(of: EduNodeType.toolkit, in: file.data) >= 2
        let editingDone = hasKnowledge && hasToolkit
        let evaluationDesignDone = roles.contains("evaluation_metric")
            && roles.contains("evaluation_summary")

        let canMarkLesson = editingDone && evaluationDesignDone && roles.contains("lesson_plan")
        let canMarkEvaluation = file.lessonPlanMarkedDone
            && roles.contains("evaluation_summary")
            && roles.contains("export_ppt")
        let lessonDone = file.lessonPlanMarkedDone && canMarkLesson
        let evaluationDone = file.evaluationMarkedDone && canMarkEvaluation

        return [
            EduFlowStepState(step: .basicInfo, index: 1, isDone: basicInfoDone, isManual: false, canToggle: false),
            EduFlowStepState(step: .modelSelection, index: 2, isDone: modelDone, isManual: false, canToggle: false),
            EduFlowStepState(step: .knowledgeToolkit, index: 3, isDone: editingDone, isManual: false, canToggle: false),
            EduFlowStepState(step: .evaluationDesign, index: 4, isDone: evaluationDesignDone, isManual: false, canToggle: false),
            EduFlowStepState(step: .lessonPlan, index: 5, isDone: lessonDone, isManual: true, canToggle: canMarkLesson),
            EduFlowStepState(step: .evaluationSummary, index: 6, isDone: evaluationDone, isManual: true, canToggle: canMarkEvaluation)
        ]
    }

    private func toggleManualStep(_ step: EduFlowStep, for file: GNodeWorkspaceFile) {
        let roles = EduPlanning.roles(in: file.data)
        let editingDone = EduPlanning.filledNodeCount(of: EduNodeType.knowledge, in: file.data) >= 1
            && EduPlanning.filledNodeCount(of: EduNodeType.toolkit, in: file.data) >= 2
        let evaluationDesignDone = roles.contains("evaluation_metric")
            && roles.contains("evaluation_summary")

        switch step {
        case .lessonPlan:
            guard editingDone && evaluationDesignDone && roles.contains("lesson_plan") else { return }
            file.lessonPlanMarkedDone.toggle()
            if !file.lessonPlanMarkedDone {
                file.evaluationMarkedDone = false
            }

        case .evaluationSummary:
            guard file.lessonPlanMarkedDone
                    && roles.contains("evaluation_summary")
                    && roles.contains("export_ppt") else { return }
            file.evaluationMarkedDone.toggle()

        case .basicInfo, .modelSelection, .knowledgeToolkit, .evaluationDesign:
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

    @ViewBuilder
    private func courseContextPanel(for file: GNodeWorkspaceFile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.cyan)
                Text(S("app.context.title"))
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 4)
                Button {
                    isCourseContextExpanded.toggle()
                } label: {
                    Label(
                        isCourseContextExpanded ? S("app.context.hide") : S("app.context.show"),
                        systemImage: isCourseContextExpanded ? "chevron.down.circle.fill" : "chevron.up.circle.fill"
                    )
                    .labelStyle(.iconOnly)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if isCourseContextExpanded {
                contextRow(label: S("course.subject"), value: file.subject)
                contextRow(label: S("course.gradeMode"), value: gradeSummary(for: file))
                contextRow(label: S("course.studentCount"), value: "\(file.studentCount)")
                contextRow(label: S("course.duration"), value: "\(file.lessonDurationMinutes) min")
                contextRow(label: S("app.context.model"), value: modelSummary(for: file))

                VStack(alignment: .leading, spacing: 4) {
                    Text(S("app.context.goals"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    let goals = goalItems(for: file)
                    if goals.isEmpty {
                        Text(S("app.context.none"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(goals.prefix(3).enumerated()), id: \.offset) { _, goal in
                            Text("• \(goal)")
                                .font(.caption2)
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: isCourseContextExpanded ? 300 : 170, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 10, y: 2)
    }

    @ViewBuilder
    private func contextRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? S("app.context.none") : value)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
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

    private func S(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    private func emptyDocumentData() -> Data {
        let document = GNodeDocument(nodes: [], connections: [], canvasState: [])
        return (try? encodeDocument(document)) ?? Data()
    }
}

#Preview {
    ContentView()
}
