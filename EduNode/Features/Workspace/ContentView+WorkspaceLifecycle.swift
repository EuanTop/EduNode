import SwiftUI
import GNodeKit
import SwiftData

extension ContentView {
    @ViewBuilder
    var presentationStylingFullScreenPage: some View {
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

                    if activeTutorial != nil && !isTutorialInDocsPhase {
                        tutorialCoachMarkOverlay
                            .zIndex(3200)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
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

    var selectedWorkspaceFile: GNodeWorkspaceFile? {
        if let selectedFileID {
            return workspaceFiles.first(where: { $0.id == selectedFileID })
        }
        return workspaceFiles.first
    }

    var selectedModelTemplatePreview: ModelTemplatePreview? {
        guard let selectedModelTemplatePreviewID else { return nil }
        return modelTemplatePreviewByID[selectedModelTemplatePreviewID]
    }

    func presentCreateCourseSheet() {
        if isTutorialPracticeAwaitingCourseCreation {
            creationDraft = tutorialPracticeDraft()
        } else {
            creationDraft = CourseCreationDraft()
        }
        showingCreateCourseSheet = true
    }

    func showModelTemplatePreview(_ rule: EduModelRule) {
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

    func modelTemplatePreviewDraft(for rule: EduModelRule, isChinese: Bool) -> CourseCreationDraft {
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

    func previewSubject(for rule: EduModelRule, isChinese: Bool) -> String {
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
    func sidebarModelTemplatePreviewRow(rule: EduModelRule) -> some View {
        let chinese = isChineseUI()
        let isSelected = selectedModelTemplatePreviewID == rule.id
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSelected ? "square.grid.3x3.fill" : "square.grid.3x3")
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .font(.body.weight(.semibold))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.displayName(isChinese: chinese))
                    .font(isSelected ? .body.weight(.semibold) : .body)
                    .foregroundColor(isSelected ? .accentColor : .primary)
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
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    @ViewBuilder
    func modelTemplatePreviewDetailView(
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
        .toolbar(.hidden, for: .navigationBar)
        .background(Color(white: 0.1))
    }

    func createWorkspaceFileFromDraft() {
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
            evaluationMarkedDone: false,
            totalSessions: creationDraft.totalSessions,
            lessonType: creationDraft.lessonType.rawValue,
            teachingStyle: creationDraft.teachingStyle.rawValue,
            formativeCheckIntensity: creationDraft.formativeCheckIntensity.rawValue,
            emphasizeInquiryExperiment: creationDraft.emphasizeInquiryExperiment,
            emphasizeExperienceReflection: creationDraft.emphasizeExperienceReflection,
            requireStructuredFlow: creationDraft.requireStructuredFlow
        )

        modelContext.insert(file)
        try? modelContext.save()

        selectedFileID = file.id
        showingCreateCourseSheet = false

        if activeTutorial == .practice {
            tutorialPracticeFileID = file.id
            tutorialPracticeBaselineSemanticData = tutorialSemanticSnapshotData(from: data)
            tutorialPracticeHasEnteredPresentation = false
            tutorialPracticeConfiguredToolkitNodeID = nil
            tutorialPracticeKnowledgeModificationBaseline = nil
            tutorialPracticeKnowledgeStepTargetNodeID = nil
            tutorialPracticeKnowledgeStepEntryContent = nil
            tutorialPracticeConnectionStepBaseline = nil
            tutorialPracticeInitialZoomPercent = editorStatsByFileID[file.id]?.zoomPercent ?? 100
            tutorialPracticeZoomStepBaseline = nil
            if let document = try? decodeDocument(from: data) {
                tutorialPracticeInitialToolkitCount = document.nodes.filter { EduNodeType.allToolkitTypes.contains($0.nodeType) }.count
                tutorialPracticeInitialConnections = tutorialConnectionSignatures(in: document)
                tutorialPracticeInitialNodeIDs = Set(document.nodes.map(\.id))
                tutorialPracticeInitialKnowledgeContentByNodeID = tutorialKnowledgeContentByNodeID(in: document)
                tutorialPracticeTopKnowledgeNodeIDs = tutorialPracticeTopKnowledgeNodeIDs(in: document)
            } else {
                tutorialPracticeInitialToolkitCount = 0
                tutorialPracticeInitialConnections = []
                tutorialPracticeInitialNodeIDs = []
                tutorialPracticeInitialKnowledgeContentByNodeID = [:]
                tutorialPracticeTopKnowledgeNodeIDs = []
            }
            if tutorialStepIndex < practiceSteps.count,
               practiceSteps[tutorialStepIndex].advanceMode == .waitForCourseCreated {
                advanceTutorialStep()
            }
        }
    }

    func completeOnboardingGuide() {
        showingOnboardingGuide = false
        didCompleteOnboarding = true
    }

    func dismissOnboardingGuideForNow() {
        showingOnboardingGuide = false
    }

    func createPhysicsMicroLessonTrainingFile() {
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

    func seedDefaultCourseIfNeeded() {
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
        let teacherRolePlan = zhuhaiSampleTeacherRolePlan(isChinese: isChinese)

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
            periodRange: isChinese ? "器材：望远镜6台、鸟类图鉴3套、巢材包28份；需室内 + 户外场地" : "Equipment: 6 binoculars, 3 field guides, 28 nest kits; indoor + outdoor venue needed",
            studentCount: 28,
            studentProfile: zhuhaiSampleStudentProfile(isChinese: isChinese),
            studentPriorKnowledgeLevel: "60",
            studentMotivationLevel: "85",
            studentSupportNotes: isChinese ? "低龄组增加助教支持与结构示范。" : "Provide extra TA support and structure demo for younger groups.",
            goalsText: goals,
            modelID: "fivee",
            teacherTeam: zhuhaiSampleTeacherTeamSummary(isChinese: isChinese),
            leadTeacherCount: 2,
            assistantTeacherCount: 9,
            teacherRolePlan: teacherRolePlan,
            learningScenario: "",
            curriculumStandard: "",
            resourceConstraints: isChinese ? "器材：望远镜6台、鸟类图鉴3套、巢材包28份；需室内 + 户外场地" : "Equipment: 6 binoculars, 3 field guides, 28 nest kits; indoor + outdoor venue needed",
            knowledgeToolkitMarkedDone: true,
            lessonPlanMarkedDone: false,
            evaluationMarkedDone: false,
            totalSessions: 1,
            lessonType: "singleLesson",
            teachingStyle: "experientialReflective",
            formativeCheckIntensity: "medium",
            emphasizeInquiryExperiment: true,
            emphasizeExperienceReflection: true,
            requireStructuredFlow: true
        )

        modelContext.insert(file)
        try? modelContext.save()
        selectedFileID = file.id
        didSeedDefaultCourse = true
    }

    func syncSelectedWorkspaceFile() {
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

    func requestCameraFocusOnFirstNodeForSelectedFile() {
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

    func firstCanvasNodePosition(from graphData: Data) -> CGPoint? {
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

    func migrateWorkspaceFilesIfNeeded() {
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

            if EduPlanning.isZhuhaiSampleData(file.data),
               shouldUpgradeZhuhaiTeamRoster(for: file) {
                let isChinese = inferredChinesePreference(for: file)
                file.studentCount = 28
                file.studentProfile = zhuhaiSampleStudentProfile(isChinese: isChinese)
                file.studentPriorKnowledgeLevel = "60"
                file.studentMotivationLevel = "85"
                file.studentSupportNotes = isChinese
                    ? "低龄组增加助教支持与结构示范。"
                    : "Provide extra TA support and structure demo for younger groups."
                file.teacherTeam = zhuhaiSampleTeacherTeamSummary(isChinese: isChinese)
                file.leadTeacherCount = 2
                file.assistantTeacherCount = 9
                file.teacherRolePlan = zhuhaiSampleTeacherRolePlan(isChinese: isChinese)
                file.updatedAt = .now
                didChange = true
            }
        }
        if didChange {
            try? modelContext.save()
        }
    }

    func hydratePresentationStateFromStoreIfNeeded() {
        for file in workspaceFiles {
            hydratePresentationState(for: file, force: false)
        }
    }

    func hydratePresentationState(for file: GNodeWorkspaceFile, force: Bool) {
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

    func persistAllPresentationStates() {
        for file in workspaceFiles {
            persistPresentationState(fileID: file.id)
        }
    }

    func persistPresentationState(fileID: UUID) {
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

    func presentationOverlayRecord(from overlay: PresentationSlideOverlay) -> PresentationPersistedOverlay {
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

    func remappedPresentationGroupStates(
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

    func hydratedPresentationGroupState(
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

    func presentationGroupSignature(_ group: EduPresentationSlideGroup) -> String {
        group.sourceSlides.map { $0.id.uuidString }.joined(separator: "|")
    }

    func finiteDouble(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? value : fallback
    }

    func clampedFiniteDouble(_ value: Double, range: ClosedRange<Double>, fallback: Double) -> Double {
        let finite = finiteDouble(value, fallback: fallback)
        return min(range.upperBound, max(range.lowerBound, finite))
    }

    func normalizedPersistentImageData(_ data: Data) -> Data {
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
    func imageHasAlpha(_ image: UIImage) -> Bool {
        guard let alphaInfo = image.cgImage?.alphaInfo else { return false }
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        default:
            return false
        }
    }
    #endif

    func presentationStateDecodeCandidates(for file: GNodeWorkspaceFile) -> [(source: String, data: Data)] {
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

    func resolvedInlinePresentationStateData(_ raw: Data) -> Data {
        guard !raw.isEmpty else { return Data() }
        guard let marker = String(data: raw, encoding: .utf8),
              marker.hasPrefix(presentationStateMarkerPrefix) else {
            return raw
        }
        return Data()
    }

    var presentationStateMarkerPrefix: String {
        "edunode.presentation.sidecar:"
    }

    func presentationStateInlineMarkerData(fileID: UUID) -> Data {
        Data("\(presentationStateMarkerPrefix)\(fileID.uuidString)".utf8)
    }

    func preferredPresentationPersistedCandidate(
        _ candidates: [(source: String, data: Data, payload: PresentationPersistedState)]
    ) -> (source: String, data: Data, payload: PresentationPersistedState)? {
        candidates.max(by: { lhs, rhs in
            presentationPersistedCandidateSortsAscending(lhs: lhs, rhs: rhs)
        })
    }

    func presentationPersistedCandidateSortsAscending(
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

    func presentationStateDirectoryURL() -> URL? {
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

    func presentationStateSidecarURL(fileID: UUID) -> URL? {
        guard let directory = presentationStateDirectoryURL() else {
            if presentationPersistenceDebugEnabled {
                persistenceLog("❌ No PresentationState directory available for file \(fileID).", force: true)
            }
            return nil
        }
        return directory.appendingPathComponent("\(fileID.uuidString).json")
    }

    func loadPresentationStateFromSidecar(fileID: UUID) -> Data? {
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
    func writePresentationStateToSidecar(fileID: UUID, data: Data) -> Bool {
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

    func removePresentationStateSidecar(fileID: UUID) {
        guard let url = presentationStateSidecarURL(fileID: fileID) else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            persistenceLog("⚠️ Failed to remove presentation sidecar for file \(fileID): \(error)", force: true)
        }
    }

    func persistenceLog(_ message: String, force: Bool = false) {
        guard force || presentationPersistenceDebugEnabled else { return }
        let tagged = "EDUNODE_PERSIST | \(message)"
        lastPersistLog = tagged
        print(tagged)
        NSLog("%@", tagged)
        appendDiagnosticLogLine(tagged)
    }

    func appendDiagnosticLogLine(_ line: String) {
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

    func presentationOverlay(from record: PresentationPersistedOverlay) -> PresentationSlideOverlay {
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

    func deleteWorkspaceFile(_ file: GNodeWorkspaceFile) {
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

    func persistWorkspaceFileData(id: UUID, data: Data) {
        guard let file = workspaceFiles.first(where: { $0.id == id }) else { return }
        guard file.data != data else { return }

        file.data = data
        file.updatedAt = .now
        try? modelContext.save()
        handleTutorialDocumentDataPersisted(fileID: id, data: data)
    }

    func importWorkspaceFile(data: Data, suggestedName: String) {
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

    func flowStates(for file: GNodeWorkspaceFile) -> [EduFlowStepState] {
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

    func toggleManualStep(_ step: EduFlowStep, for file: GNodeWorkspaceFile) {
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

    func isBasicInfoComplete(_ file: GNodeWorkspaceFile) -> Bool {
        !file.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        file.gradeMin > 0 &&
        file.gradeMax >= file.gradeMin &&
        !file.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        file.lessonDurationMinutes > 0 &&
        file.studentCount > 0 &&
        !file.goalsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func handleFlowStepTap(_ step: EduFlowStep, for file: GNodeWorkspaceFile) {
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

    func confirmPendingFlowStep() {
        guard let step = pendingFlowStepConfirmation,
              let fileID = pendingFlowStepFileID,
              let file = workspaceFiles.first(where: { $0.id == fileID }) else {
            clearPendingFlowStepConfirmation()
            return
        }

        toggleManualStep(step, for: file)
        clearPendingFlowStepConfirmation()
    }

    func clearPendingFlowStepConfirmation() {
        pendingFlowStepConfirmation = nil
        pendingFlowStepFileID = nil
        pendingFlowStepIsDone = false
    }

    @ViewBuilder
    func sidebarFileRow(_ file: GNodeWorkspaceFile) -> some View {
        let isSelected = selectedFileID == file.id
        let iconName = subjectIconName(for: file.subject, filled: isSelected)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.body.weight(.semibold))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name)
                        .font(isSelected ? .body.weight(.semibold) : .body)
                        .foregroundColor(isSelected ? .accentColor : .primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isSelected {
                    Spacer(minLength: 4)
                    Button {
                        openCourseEditor(for: file)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.body)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 1)
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

    func subjectIconName(for subject: String, filled: Bool) -> String {
        let key = subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "数学", "mathematics", "math":
            return "x.squareroot"
        case "物理", "physics":
            return "atom"
        case "化学", "chemistry":
            return filled ? "flask.fill" : "flask"
        case "生物", "biology":
            return filled ? "leaf.fill" : "leaf"
        case "历史", "history":
            return "clock.arrow.circlepath"
        case "地理", "geography":
            return filled ? "globe.asia.australia.fill" : "globe.asia.australia"
        case "政治", "civics":
            return filled ? "person.3.fill" : "person.3"
        case "信息技术", "computer science":
            return "desktopcomputer"
        case "美术", "art":
            return filled ? "paintpalette.fill" : "paintpalette"
        case "音乐", "music":
            return "music.note"
        case "体育", "physical education", "pe":
            return "figure.run"
        case "通识教育", "liberal arts":
            return filled ? "books.vertical.fill" : "books.vertical"
        case "工程基础", "engineering":
            return filled ? "gearshape.2.fill" : "gearshape.2"
        case "语文", "chinese":
            return filled ? "character.book.closed.fill" : "character.book.closed"
        case "英语", "english":
            return "textformat.abc"
        case "综合实践（美育）", "综合实践", "integrated practice", "integrated practice (aesthetic education)":
            return filled ? "paintpalette.fill" : "paintpalette"
        default:
            return filled ? "doc.text.fill" : "doc.text"
        }
    }

    func fileSubtitle(_ file: GNodeWorkspaceFile) -> String {
        let subjectPart = file.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let gradePrefix = file.gradeMode == "age" ? S("course.gradeMode.age") : S("course.gradeMode.grade")
        let gradePart = "\(gradePrefix) \(file.gradeMin)-\(file.gradeMax)"

        if !subjectPart.isEmpty || !gradePart.isEmpty {
            let info = [subjectPart, gradePart].filter { !$0.isEmpty }.joined(separator: " · ")
            return info
        }

        return file.updatedAt.formatted(.dateTime.month().day().hour().minute())
    }

    func gradeSummary(for file: GNodeWorkspaceFile) -> String {
        let mode = file.gradeMode == "age" ? S("course.gradeMode.age") : S("course.gradeMode.grade")
        return "\(mode) \(file.gradeMin)-\(file.gradeMax)"
    }

    func modelSummary(for file: GNodeWorkspaceFile) -> String {
        let isChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        if let rule = modelRules.first(where: { $0.id == file.modelID }) {
            return rule.displayName(isChinese: isChinese)
        }
        return file.modelID
    }

    func goalItems(for file: GNodeWorkspaceFile) -> [String] {
        file.goalsText
            .split(whereSeparator: { $0 == "\n" || $0 == ";" || $0 == "；" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func zhuhaiSampleGoals(isChinese: Bool) -> String {
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

    func zhuhaiSampleRosterText(isChinese: Bool) -> String {
        if isChinese {
            return """
1|林晨|A组|6
2|陈雨|A组|6
3|张宁|A组|7
4|赵敏|A组|7
5|王涵|B组|7
6|李哲|B组|8
7|周悦|B组|8
8|吴昊|B组|8
9|郑琪|C组|9
10|孙朗|C组|9
11|马慧|C组|9
12|何然|C组|10
13|高宁|D组|10
14|梁嘉|D组|10
15|谢然|D组|11
16|蒋可|D组|11
17|宋宇|E组|11
18|彭颖|E组|12
19|许凡|E组|12
20|邓欣|E组|12
21|冯泽|F组|13
22|曹悦|F组|13
23|罗晨|F组|12
24|龚琳|F组|11
25|戴航|G组|9
26|韩雪|G组|10
27|余澄|G组|11
28|潘诺|G组|13
"""
        }

        return """
1|Lin Chen|Group A|6
2|Rain Chen|Group A|6
3|Ning Zhang|Group A|7
4|Min Zhao|Group A|7
5|Han Wang|Group B|7
6|Zhe Li|Group B|8
7|Yue Zhou|Group B|8
8|Hao Wu|Group B|8
9|Qi Zheng|Group C|9
10|Lang Sun|Group C|9
11|Hui Ma|Group C|9
12|Ran He|Group C|10
13|Ning Gao|Group D|10
14|Jia Liang|Group D|10
15|Ran Xie|Group D|11
16|Ke Jiang|Group D|11
17|Yu Song|Group E|11
18|Ying Peng|Group E|12
19|Fan Xu|Group E|12
20|Xin Deng|Group E|12
21|Ze Feng|Group F|13
22|Yue Cao|Group F|13
23|Chen Luo|Group F|12
24|Lin Gong|Group F|11
25|Hang Dai|Group G|9
26|Xue Han|Group G|10
27|Cheng Yu|Group G|11
28|Nuo Pan|Group G|13
"""
    }

    func zhuhaiSampleTeacherRolePlan(isChinese: Bool) -> String {
        if isChinese {
            return """
主讲 | 陈老师 | 负责课程主线推进、关键提问与概念收束
主讲 | 王老师 | 负责实验演示节奏控制与全班讲解
助教 | 刘老师（A组） | 负责 A 组观察记录、搭建支持与安全提醒
助教 | 李老师（B组） | 负责 B 组观察记录、搭建支持与安全提醒
助教 | 张老师（C组） | 负责 C 组观察记录、搭建支持与安全提醒
助教 | 赵老师（D组） | 负责 D 组观察记录、搭建支持与安全提醒
助教 | 周老师（E组） | 负责 E 组观察记录、搭建支持与安全提醒
助教 | 吴老师（F组） | 负责 F 组观察记录、搭建支持与安全提醒
助教 | 郑老师（G组） | 负责 G 组观察记录、搭建支持与安全提醒
助教 | 徐老师（摄影） | 负责课堂摄影、作品采样与过程档案记录
助教 | 何老师（机动） | 负责机动支援、材料调配与全场安全巡检
"""
        }

        return """
Lead | Ms. Chen | Drive the main storyline, key questioning, and concept synthesis
Lead | Mr. Wang | Control demo pacing and whole-class explanation
Assistant | Ms. Liu (Group A) | Support observation notes, nest building, and safety checks for Group A
Assistant | Mr. Li (Group B) | Support observation notes, nest building, and safety checks for Group B
Assistant | Ms. Zhang (Group C) | Support observation notes, nest building, and safety checks for Group C
Assistant | Mr. Zhao (Group D) | Support observation notes, nest building, and safety checks for Group D
Assistant | Ms. Zhou (Group E) | Support observation notes, nest building, and safety checks for Group E
Assistant | Mr. Wu (Group F) | Support observation notes, nest building, and safety checks for Group F
Assistant | Ms. Zheng (Group G) | Support observation notes, nest building, and safety checks for Group G
Assistant | Mr. Xu (Photo) | Handle in-class photography, artifact capture, and process archiving
Assistant | Ms. He (Floater) | Provide floating support, material dispatch, and safety backup
"""
    }

    func zhuhaiSampleStudentProfile(isChinese: Bool) -> String {
        let notes = isChinese
            ? "低龄组增加助教支持与结构示范。"
            : "Provide extra TA support and structure demo for younger groups."
        let outputs = isChinese ? "学生作品集,课堂展示" : "portfolio,presentation"
        return "priorScore=60, completion=85, supportNeed=4, notes=\(notes), roster=\(zhuhaiSampleRosterText(isChinese: isChinese)), organization=mixed, outputs=\(outputs)"
    }

    func zhuhaiSampleTeacherTeamSummary(isChinese: Bool) -> String {
        if isChinese {
            return "lead=2, assistant=9, plan=2位主讲 + 7位分组助教 + 1位摄影 + 1位机动支援。"
        }
        return "lead=2, assistant=9, plan=2 leads + 7 group TAs + 1 photo TA + 1 floating TA."
    }

    func zhuhaiLegacyGoals(isChinese: Bool) -> String {
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

    func normalizedMultiline(_ value: String) -> String {
        value
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    func inferredChinesePreference(for file: GNodeWorkspaceFile) -> Bool {
        let candidate = "\(file.name)\n\(file.subject)\n\(file.goalsText)"
        if candidate.range(of: #"[一-龥]"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    func shouldUpgradeZhuhaiGoals(for file: GNodeWorkspaceFile) -> Bool {
        let current = normalizedMultiline(file.goalsText)
        if current.isEmpty { return true }
        let oldChinese = normalizedMultiline(zhuhaiLegacyGoals(isChinese: true))
        let oldEnglish = normalizedMultiline(zhuhaiLegacyGoals(isChinese: false))
        return current == oldChinese || current == oldEnglish
    }

    func shouldUpgradeZhuhaiTeamRoster(for file: GNodeWorkspaceFile) -> Bool {
        let rosterEntries = parsedStudentRosterEntries(from: file.studentProfile)
        let rosterCountMatches = rosterEntries.count == 28
        let groupCount = Set(
            rosterEntries
                .map { $0.group.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        ).count
        let groupCountMatches = groupCount == 7
        let teacherCountMatches = file.leadTeacherCount == 2 && file.assistantTeacherCount == 9

        let planLower = file.teacherRolePlan.lowercased()
        let hasPhotoRole = planLower.contains("摄影") || planLower.contains("photo")
        let hasFloatingRole = planLower.contains("机动") || planLower.contains("float")
        let hasCompletePlan = hasPhotoRole && hasFloatingRole

        return !(rosterCountMatches && groupCountMatches && teacherCountMatches && hasCompletePlan)
    }

    func effectiveGoals(for file: GNodeWorkspaceFile) -> [String] {
        let goals = goalItems(for: file)
        if !goals.isEmpty { return goals }
        if EduPlanning.isZhuhaiSampleData(file.data) {
            return zhuhaiSampleGoals(isChinese: inferredChinesePreference(for: file))
                .split(whereSeparator: \.isNewline)
                .map { String($0) }
        }
        return []
    }

    func isChineseUI() -> Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    @ViewBuilder
    func sidebarCourseContextCard(file: GNodeWorkspaceFile) -> some View {
        let goals = effectiveGoals(for: file)
        let visibleGoals = Array(goals.prefix(8))
        let model = modelSummary(for: file)
        let subject = file.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = file.periodRange.trimmingCharacters(in: .whitespacesAndNewlines)
        let constraints = file.resourceConstraints.trimmingCharacters(in: .whitespacesAndNewlines)
        let subjectDisplay = subject.isEmpty ? S("app.context.none") : subject
        let notesDisplay = notes.isEmpty ? nil : notes
        let constraintsDisplay = constraints.isEmpty ? nil : constraints
        let isCN = isChineseUI()

        VStack(alignment: .leading, spacing: 8) {
            Button {
                isSidebarBasicInfoExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text(S("flow.basicInfo"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Spacer(minLength: 8)
                    Image(systemName: isSidebarBasicInfoExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSidebarBasicInfoExpanded {
                VStack(alignment: .leading, spacing: 7) {
                    sidebarContextRow(label: isCN ? "学科" : "Subject", value: subjectDisplay)
                    sidebarContextRow(label: isCN ? "学段" : "Range", value: gradeSummary(for: file))
                    sidebarContextRow(label: isCN ? "学生" : "Students", value: "\(file.studentCount)" + (isCN ? "人" : ""))
                    sidebarContextRow(label: isCN ? "课型" : "Type", value: lessonTypeDisplayName(file.lessonType, isChinese: isCN))
                    sidebarContextRow(
                        label: isCN ? "时长" : "Duration",
                        value: file.totalSessions > 1
                            ? "\(file.lessonDurationMinutes)min × \(file.totalSessions)"
                            : "\(file.lessonDurationMinutes)min"
                    )
                    sidebarContextRow(label: isCN ? "教学风格" : "Style", value: teachingStyleDisplayName(file.teachingStyle, isChinese: isCN))
                    sidebarContextRow(label: isCN ? "检查强度" : "Check", value: formativeCheckDisplayName(file.formativeCheckIntensity, isChinese: isCN))
                    sidebarContextRow(label: isCN ? "模型" : "Model", value: model)
                    sidebarContextRow(
                        label: isCN ? "教师" : "Team",
                        value: "\(file.leadTeacherCount)" + (isCN ? "主讲" : " lead") + " + \(file.assistantTeacherCount)" + (isCN ? "助教" : " TA")
                    )
                    if let notesDisplay {
                        sidebarContextRow(label: isCN ? "备注" : "Notes", value: notesDisplay)
                    }
                    if let constraintsDisplay {
                        sidebarContextRow(label: isCN ? "资源" : "Resources", value: constraintsDisplay)
                    }
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
    func editorStatsOverlay(stats: NodeEditorCanvasStats) -> some View {
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
    var presentationPreparingOverlay: some View {
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
    func sidebarContextRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.caption2.weight(.semibold))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func lessonTypeDisplayName(_ raw: String, isChinese: Bool) -> String {
        switch raw {
        case "singleLesson": return isChinese ? "单节课" : "Single Lesson"
        case "unitSeries": return isChinese ? "单元连续课" : "Unit Series"
        default: return isChinese ? "单节课" : "Single Lesson"
        }
    }

    func teachingStyleDisplayName(_ raw: String, isChinese: Bool) -> String {
        switch raw {
        case "lectureDriven": return isChinese ? "讲授驱动" : "Lecture-driven"
        case "inquiryDriven": return isChinese ? "探究驱动" : "Inquiry-driven"
        case "experientialReflective": return isChinese ? "体验-反思" : "Experience-reflection"
        case "taskDriven": return isChinese ? "任务驱动" : "Task-driven"
        default: return raw
        }
    }

    func formativeCheckDisplayName(_ raw: String, isChinese: Bool) -> String {
        switch raw {
        case "low": return isChinese ? "低" : "Low"
        case "medium": return isChinese ? "中" : "Medium"
        case "high": return isChinese ? "高" : "High"
        default: return raw
        }
    }


}
