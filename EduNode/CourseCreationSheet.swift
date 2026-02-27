import SwiftUI
import UniformTypeIdentifiers

enum CourseFormPage: Int, CaseIterable {
    case basics
    case goalsOutputs
    case modelInputs
    case model
    case teamStudents

    func title(_ S: (String) -> String) -> String {
        switch self {
        case .basics:
            return S("course.page.basics")
        case .goalsOutputs:
            return S("course.page.goalsOutputs")
        case .modelInputs:
            return S("course.page.modelInputs")
        case .model:
            return S("course.page.modelFit")
        case .teamStudents:
            return S("course.page.teamStudents")
        }
    }
}

private enum TeacherRoleType: String, CaseIterable {
    case lead
    case assistant

    func title(isChinese: Bool) -> String {
        switch self {
        case .lead:
            return isChinese ? "主讲" : "Lead"
        case .assistant:
            return isChinese ? "助教" : "Assistant"
        }
    }
}

private struct TeacherRoleRow: Identifiable, Equatable {
    let id: UUID
    var roleType: TeacherRoleType
    var teacherName: String
    var responsibility: String

    init(
        id: UUID = UUID(),
        roleType: TeacherRoleType,
        teacherName: String = "",
        responsibility: String = ""
    ) {
        self.id = id
        self.roleType = roleType
        self.teacherName = teacherName
        self.responsibility = responsibility
    }
}

private enum GoalPresetType: String, CaseIterable {
    case conceptUnderstanding
    case applicationTransfer
    case inquiryReasoning
    case processSkill
    case collaborationCommunication
    case reflectionMetacognition
    case custom
}

private struct GoalDraftRow: Identifiable, Equatable {
    let id: UUID
    var preset: GoalPresetType
    var detail: String

    init(id: UUID = UUID(), preset: GoalPresetType, detail: String = "") {
        self.id = id
        self.preset = preset
        self.detail = detail
    }
}

private enum ExpectedOutputPreset: String, CaseIterable {
    case worksheet
    case experimentLog
    case presentation
    case projectArtifact
    case lessonHandout
    case custom
}

private struct StudentRosterRow: Identifiable, Equatable {
    let id: UUID
    var name: String
    var group: String
    var ageText: String

    init(id: UUID = UUID(), name: String = "", group: String = "", ageText: String = "") {
        self.id = id
        self.name = name
        self.group = group
        self.ageText = ageText
    }
}

@MainActor
struct CourseCreationSheet: View {
    @Binding var draft: CourseCreationDraft
    let modelRules: [EduModelRule]
    let onCancel: () -> Void
    let onCreate: () -> Void
    var initialPage: CourseFormPage = .basics
    var onSaveRoster: ((String) -> Void)? = nil

    @State private var page: CourseFormPage = .basics
    @State private var selectedSubjectPreset = "__custom__"
    @State private var goalRows: [GoalDraftRow] = []
    @State private var selectedExpectedOutputs: Set<ExpectedOutputPreset> = []
    @State private var customExpectedOutputText = ""
    @State private var studentRows: [StudentRosterRow] = []
    @State private var showAllModelsInline = false
    @State private var teacherRoleRows: [TeacherRoleRow] = []
    @State private var isSubjectDropdownExpanded = false
    @State private var expandedGoalRowID: UUID?
    @State private var expandedRoleRowID: UUID?
    @State private var expandedStudentGroupRowID: UUID?
    @State private var pendingStudentGroupTextByRowID: [UUID: String] = [:]
    @State private var showingStudentCSVImporter = false

    private let customSubjectTag = "__custom__"
    private let subjectDropdownID = "course.subject.dropdown"

    private struct ActiveCourseDropdownPayload {
        let id: String
        let options: [CourseFormDropdownOption]
        let selection: Binding<String>
        let textFont: Font
        let panelWidth: CGFloat?
    }

    private func roleDropdownID(_ rowID: UUID) -> String {
        "course.role.\(rowID.uuidString)"
    }

    private func goalPresetDropdownID(_ rowID: UUID) -> String {
        "course.goal.\(rowID.uuidString)"
    }

    private struct HeaderArtItem {
        let name: String
        let widthRatio: CGFloat
        let xOffsetRatio: CGFloat
        let yOffset: CGFloat
        let rotation: Double
        let opacity: Double
    }

    private var isChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    private var subjectPresets: [String] {
        if isChinese {
            return [
                "数学", "物理", "化学", "生物", "历史", "地理", "政治",
                "信息技术", "美术", "音乐", "体育", "通识教育", "工程基础", "语文", "英语"
            ]
        }

        return [
            "Mathematics", "Physics", "Chemistry", "Biology", "History", "Geography", "Civics",
            "Computer Science", "Art", "Music", "Physical Education", "Liberal Arts", "Engineering", "English", "Chinese"
        ]
    }

    private var subjectDropdownOptions: [CourseFormDropdownOption] {
        subjectPresets.map { CourseFormDropdownOption(value: $0, title: $0) }
        + [CourseFormDropdownOption(value: customSubjectTag, title: S("course.subjectCustom"))]
    }

    private var subjectSelectionBinding: Binding<String> {
        Binding(
            get: { selectedSubjectPreset },
            set: { newValue in
                selectedSubjectPreset = newValue
                if newValue != customSubjectTag {
                    draft.subject = newValue
                }
            }
        )
    }

    private var goalPresetOptions: [CourseFormDropdownOption] {
        GoalPresetType.allCases.map { preset in
            CourseFormDropdownOption(value: preset.rawValue, title: goalPresetTitle(preset))
        }
    }

    private var expectedOutputOptions: [ExpectedOutputPreset] {
        ExpectedOutputPreset.allCases
    }

    private func goalPresetTitle(_ preset: GoalPresetType) -> String {
        switch preset {
        case .conceptUnderstanding:
            return isChinese ? "概念理解" : "Concept Understanding"
        case .applicationTransfer:
            return isChinese ? "应用迁移" : "Application Transfer"
        case .inquiryReasoning:
            return isChinese ? "探究推理" : "Inquiry Reasoning"
        case .processSkill:
            return isChinese ? "过程技能" : "Process Skill"
        case .collaborationCommunication:
            return isChinese ? "协作表达" : "Collaboration & Communication"
        case .reflectionMetacognition:
            return isChinese ? "反思元认知" : "Reflection & Metacognition"
        case .custom:
            return isChinese ? "自定义目标" : "Custom Goal"
        }
    }

    private func expectedOutputTitle(_ preset: ExpectedOutputPreset) -> String {
        switch preset {
        case .worksheet:
            return isChinese ? "练习单/作业单" : "Worksheet"
        case .experimentLog:
            return isChinese ? "实验记录" : "Experiment Log"
        case .presentation:
            return isChinese ? "汇报展示" : "Presentation"
        case .projectArtifact:
            return isChinese ? "项目作品" : "Project Artifact"
        case .lessonHandout:
            return isChinese ? "课堂讲义" : "Lesson Handout"
        case .custom:
            return isChinese ? "自定义" : "Custom"
        }
    }

    private func lessonTypeTitle(_ type: CourseLessonType) -> String {
        switch type {
        case .singleLesson:
            return isChinese ? "单节课" : "Single Lesson"
        case .unitSeries:
            return isChinese ? "单元连续课" : "Unit Series"
        }
    }

    private func learningOrganizationTitle(_ mode: LearningOrganizationMode) -> String {
        switch mode {
        case .individual:
            return isChinese ? "个人" : "Individual"
        case .group:
            return isChinese ? "小组" : "Group"
        case .mixed:
            return isChinese ? "混合" : "Mixed"
        }
    }

    private func teachingStyleTitle(_ mode: TeachingStyleMode) -> String {
        switch mode {
        case .lectureDriven:
            return isChinese ? "讲授驱动" : "Lecture-driven"
        case .inquiryDriven:
            return isChinese ? "探究驱动" : "Inquiry-driven"
        case .experientialReflective:
            return isChinese ? "体验-反思驱动" : "Experience-reflection"
        case .taskDriven:
            return isChinese ? "任务驱动" : "Task-driven"
        }
    }

    private func formativeCheckTitle(_ value: FormativeCheckIntensity) -> String {
        switch value {
        case .low:
            return isChinese ? "低" : "Low"
        case .medium:
            return isChinese ? "中" : "Medium"
        case .high:
            return isChinese ? "高" : "High"
        }
    }

    private var recommended: [EduModelRule] {
        EduPlanning.recommendedModels(for: draft, rules: modelRules)
    }

    private var toolkitPresetLookup: [String: EduToolkitPreset] {
        Dictionary(uniqueKeysWithValues: EduPlanning.toolkitPresets().map { ($0.id, $0) })
    }

    private var pages: [CourseFormPage] {
        CourseFormPage.allCases
    }

    private var headerArtItems: [HeaderArtItem] {
        switch page {
        case .basics:
            return [
                HeaderArtItem(name: "cap", widthRatio: 3.30, xOffsetRatio: -0.33, yOffset: 10, rotation: -34, opacity: 0.30),
                HeaderArtItem(name: "book", widthRatio: 2.10, xOffsetRatio: 0.48, yOffset: 78, rotation: 22, opacity: 0.20)
            ]
        case .goalsOutputs:
            return [
                HeaderArtItem(name: "tellurion", widthRatio: 3.10, xOffsetRatio: -0.30, yOffset: 12, rotation: -31, opacity: 0.28),
                HeaderArtItem(name: "book", widthRatio: 2.05, xOffsetRatio: 0.48, yOffset: 76, rotation: 25, opacity: 0.19)
            ]
        case .modelInputs:
            return [
                HeaderArtItem(name: "bulb", widthRatio: 3.16, xOffsetRatio: -0.31, yOffset: 10, rotation: -32, opacity: 0.30),
                HeaderArtItem(name: "chemistry", widthRatio: 2.08, xOffsetRatio: 0.48, yOffset: 78, rotation: 23, opacity: 0.20)
            ]
        case .model:
            return [
                HeaderArtItem(name: "award", widthRatio: 3.16, xOffsetRatio: -0.31, yOffset: 10, rotation: -28, opacity: 0.28),
                HeaderArtItem(name: "book", widthRatio: 2.02, xOffsetRatio: 0.48, yOffset: 78, rotation: 23, opacity: 0.18)
            ]
        case .teamStudents:
            return [
                HeaderArtItem(name: "award", widthRatio: 3.36, xOffsetRatio: -0.33, yOffset: 12, rotation: -30, opacity: 0.28),
                HeaderArtItem(name: "football", widthRatio: 2.02, xOffsetRatio: 0.49, yOffset: 76, rotation: 23, opacity: 0.20)
            ]
        }
    }

    private var pageIndex: Int {
        pages.firstIndex(of: page) ?? 0
    }

    private var activeDropdownPayload: ActiveCourseDropdownPayload? {
        if isSubjectDropdownExpanded {
            return ActiveCourseDropdownPayload(
                id: subjectDropdownID,
                options: subjectDropdownOptions,
                selection: subjectSelectionBinding,
                textFont: .subheadline,
                panelWidth: nil
            )
        }

        if let rowID = expandedGoalRowID,
           goalRows.contains(where: { $0.id == rowID }) {
            return ActiveCourseDropdownPayload(
                id: goalPresetDropdownID(rowID),
                options: goalPresetOptions,
                selection: goalPresetSelectionBinding(for: rowID),
                textFont: .subheadline,
                panelWidth: 320
            )
        }

        if let rowID = expandedRoleRowID,
           teacherRoleRows.contains(where: { $0.id == rowID }) {
            return ActiveCourseDropdownPayload(
                id: roleDropdownID(rowID),
                options: TeacherRoleType.allCases.map {
                    CourseFormDropdownOption(
                        value: $0.rawValue,
                        title: $0.title(isChinese: isChinese)
                    )
                },
                selection: roleSelectionBinding(for: rowID),
                textFont: .system(size: 13, weight: .regular),
                panelWidth: nil
            )
        }

        return nil
    }

    private var isAnyFormDropdownExpanded: Bool {
        isSubjectDropdownExpanded || expandedGoalRowID != nil || expandedRoleRowID != nil || expandedStudentGroupRowID != nil
    }

    private var canGoNext: Bool {
        switch page {
        case .basics:
            return !draft.courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !draft.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            draft.lessonDurationMinutes > 0 &&
            draft.totalSessions > 0 &&
            draft.studentCount > 0 &&
            draft.normalizedGradeRange.1 >= draft.normalizedGradeRange.0

        case .goalsOutputs:
            return !draft.goalsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !draft.expectedOutputSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        case .modelInputs:
            return true

        case .model:
            return !draft.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        case .teamStudents:
            return isTeacherTeamValid
        }
    }

    private var isTeacherTeamValid: Bool {
        let normalizedNames = teacherRoleRows
            .map { $0.teacherName.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !normalizedNames.isEmpty else { return false }
        return normalizedNames.allSatisfy { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                Group {
                    switch page {
                    case .basics:
                        basicsPage
                    case .goalsOutputs:
                        goalsOutputsPage
                    case .modelInputs:
                        modelInputsPage
                    case .model:
                        modelRecommendPage
                    case .teamStudents:
                        teamStudentsPage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(isAnyFormDropdownExpanded ? 2000 : 0)

                footer
                    .zIndex(0)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.08),
                        Color.black.opacity(0.03)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle(S("course.createTitle"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(S("action.cancel"), action: onCancel)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .onAppear {
                page = initialPage
                if draft.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let first = subjectPresets.first {
                    draft.subject = first
                }
                syncPresetSelectionWithSubject()
                initializeTeacherRoleRowsFromDraft()
                initializeGoalRowsFromDraft()
                initializeExpectedOutputsFromDraft()
                initializeStudentRowsFromDraft()

                if draft.modelID.isEmpty, let firstRecommended = recommended.first {
                    draft.modelID = firstRecommended.id
                }
            }
            .onChange(of: teacherRoleRows) { _, _ in
                if let expandedRoleRowID,
                   !teacherRoleRows.contains(where: { $0.id == expandedRoleRowID }) {
                    self.expandedRoleRowID = nil
                }
                syncDraftFromTeacherRoleRows()
            }
            .onChange(of: goalRows) { _, _ in
                syncDraftGoalsFromRows()
            }
            .onChange(of: selectedExpectedOutputs) { _, _ in
                syncDraftExpectedOutputs()
            }
            .onChange(of: customExpectedOutputText) { _, _ in
                syncDraftExpectedOutputs()
            }
            .onChange(of: studentRows) { _, _ in
                if let expandedStudentGroupRowID,
                   !studentRows.contains(where: { $0.id == expandedStudentGroupRowID }) {
                    self.expandedStudentGroupRowID = nil
                }
                syncDraftStudentRosterSummary()
            }
            .overlayPreferenceValue(CourseDropdownFieldAnchorKey.self) { anchors in
                globalDropdownOverlay(anchors: anchors)
            }
            .fileImporter(
                isPresented: $showingStudentCSVImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText, .text]
            ) { result in
                handleStudentCSVImport(result)
            }
        }
        .interactiveDismissDisabled(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(pageIndicatorText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Text(page.title(S))
                .font(.title3.weight(.bold))

            ProgressView(value: Double(pageIndex + 1), total: Double(pages.count))
                .tint(.cyan)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            GeometryReader { proxy in
                let topExtension = max(108, proxy.size.height * 1.3)
                let topBleed: CGFloat = 8
                let artSize = CGSize(width: proxy.size.width, height: proxy.size.height + topExtension + topBleed)

                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    headerBackgroundArt(for: artSize)
                }
                .frame(width: artSize.width, height: artSize.height, alignment: .top)
                .offset(y: -(topExtension + topBleed))
            }
        )
    }

    private func headerBackgroundArt(for size: CGSize) -> some View {
        ZStack {
            ForEach(Array(headerArtItems.enumerated()), id: \.offset) { _, item in
                Image(item.name)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: max(420, size.width * item.widthRatio))
                    .foregroundStyle(Color(white: 0.88))
                    .opacity(item.opacity)
                    .rotationEffect(.degrees(item.rotation))
                    .offset(
                        x: size.width * item.xOffsetRatio,
                        y: item.yOffset
                    )
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var basicsPage: some View {
        pageContainer {
            sectionCard {
                formField(S("course.name"), required: true) {
                    textInputField(
                        isChinese ? "例如：八年级牛顿第一定律" : "e.g. Newton's First Law",
                        text: $draft.courseName
                    )
                }

                formField(isChinese ? "课型" : "Lesson Type", required: true) {
                    Picker("", selection: $draft.lessonType) {
                        ForEach(CourseLessonType.allCases, id: \.rawValue) { type in
                            Text(lessonTypeTitle(type)).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            Text(isChinese ? "年级 / 年龄范围" : "Grade / Age Range")
                                .font(.subheadline.weight(.semibold))
                            Text("*")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.orange)
                        }
                        .foregroundStyle(.secondary)

                        Spacer(minLength: 0)

                        Picker("", selection: $draft.gradeInputMode) {
                            Text(S("course.gradeMode.gradeRange")).tag(GradeInputMode.grade)
                            Text(S("course.gradeMode.ageRange")).tag(GradeInputMode.age)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 210)
                    }

                    HStack(alignment: .center, spacing: 8) {
                        rangeBoundField(
                            draft.gradeInputMode == .grade ? S("course.gradeMin") : S("course.ageMin"),
                            text: digitsOnlyBinding($draft.gradeMinText)
                        )
                        Text("~")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        rangeBoundField(
                            draft.gradeInputMode == .grade ? S("course.gradeMax") : S("course.ageMax"),
                            text: digitsOnlyBinding($draft.gradeMaxText)
                        )
                    }
                }
                .padding(.top, 2)

                formField(S("course.subject"), required: true) {
                    CourseFormDropdown(
                        id: subjectDropdownID,
                        title: S("course.subject"),
                        options: subjectDropdownOptions,
                        selection: subjectSelectionBinding,
                        isExpanded: Binding(
                            get: { isSubjectDropdownExpanded },
                            set: { isOpen in
                                isSubjectDropdownExpanded = isOpen
                                if isOpen {
                                    expandedGoalRowID = nil
                                    expandedRoleRowID = nil
                                }
                            }
                        )
                    )
                    .zIndex(isSubjectDropdownExpanded ? 500 : 0)

                    if selectedSubjectPreset == customSubjectTag {
                        textInputField(
                            isChinese ? "请输入学科" : "Enter subject",
                            text: $draft.subject
                        )
                    }
                }
                .zIndex(isSubjectDropdownExpanded ? 1200 : 0)

                HStack(alignment: .top, spacing: 12) {
                    formField(S("course.duration"), required: true) {
                        numberInputField(S("course.duration"), text: $draft.lessonDurationMinutesText)
                    }
                    .frame(maxWidth: .infinity)

                    formField(S("course.studentCount"), required: true) {
                        numberInputField(S("course.studentCount"), text: $draft.studentCountText)
                    }
                    .frame(maxWidth: .infinity)
                }

                formField(isChinese ? "总课时数" : "Total Sessions", required: true) {
                    numberInputField(
                        isChinese ? "例如：1 或 6" : "e.g. 1 or 6",
                        text: $draft.totalSessionsText
                    )
                }

                formField(S("course.notes")) {
                    textInputField(
                        isChinese ? "例如：器材有限，需分组轮换；需要双语关键词。" : "e.g. Limited equipment, rotate by groups; include bilingual keywords.",
                        text: $draft.periodRange
                    )
                }
            }
        }
    }

    private var goalsOutputsPage: some View {
        pageContainer {
            sectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        HStack(spacing: 4) {
                            Text(isChinese ? "主要目标" : "Primary Goals")
                                .font(.subheadline.weight(.semibold))
                            Text("*")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.orange)
                        }
                        .foregroundStyle(.secondary)

                        Spacer(minLength: 0)

                        Button {
                            goalRows.append(GoalDraftRow(preset: .conceptUnderstanding))
                        } label: {
                            Label(isChinese ? "添加" : "Add", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            roleDivisionHeaderText(isChinese ? "目标类型" : "Goal Type")
                                .frame(width: 190, alignment: .leading)
                            roleDivisionHeaderText(isChinese ? "目标补充" : "Goal Detail")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Color.clear.frame(width: 18)
                        }

                        ForEach(Array(goalRows.indices), id: \.self) { index in
                            HStack(spacing: 8) {
                                CourseFormDropdown(
                                    id: goalPresetDropdownID(goalRows[index].id),
                                    title: isChinese ? "目标类型" : "Goal Type",
                                    options: goalPresetOptions,
                                    selection: goalPresetSelectionBinding(for: goalRows[index].id),
                                    isExpanded: Binding(
                                        get: { expandedGoalRowID == goalRows[index].id },
                                        set: { isOpen in
                                            expandedGoalRowID = isOpen ? goalRows[index].id : nil
                                            if isOpen {
                                                isSubjectDropdownExpanded = false
                                                expandedRoleRowID = nil
                                            }
                                        }
                                    )
                                )
                                .frame(width: 190, alignment: .leading)
                                .zIndex(expandedGoalRowID == goalRows[index].id ? 500 : 0)

                                TextField(
                                    isChinese ? "例如：理解质数在数学中的重要性" : "e.g. Explain why prime numbers matter",
                                    text: Binding(
                                        get: { goalRows[index].detail },
                                        set: { goalRows[index].detail = $0 }
                                    )
                                )
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
                                )

                                Button(role: .destructive) {
                                    goalRows.remove(at: index)
                                    if goalRows.isEmpty {
                                        goalRows.append(GoalDraftRow(preset: .conceptUnderstanding))
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.plain)
                                .frame(width: 18)
                            }
                            .zIndex(expandedGoalRowID == goalRows[index].id ? 1200 : 0)
                        }
                    }
                }
            }

            sectionCard {
                formField(isChinese ? "课堂组织方式" : "Learning Organization", required: true) {
                    let orderedModes: [LearningOrganizationMode] = [.individual, .mixed, .group]
                    Picker("", selection: $draft.learningOrganization) {
                        ForEach(orderedModes, id: \.rawValue) { mode in
                            Text(learningOrganizationTitle(mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            sectionCard {
                formField(isChinese ? "预期产出" : "Expected Outputs", required: true) {
                    let columns = [
                        GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .leading)
                    ]

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(expectedOutputOptions, id: \.rawValue) { output in
                            let selected = selectedExpectedOutputs.contains(output)
                            Button {
                                if selected {
                                    selectedExpectedOutputs.remove(output)
                                } else {
                                    selectedExpectedOutputs.insert(output)
                                }
                            } label: {
                                Text(expectedOutputTitle(output))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(selected ? Color.black : Color.primary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(
                                                selected
                                                ? Color.cyan.opacity(0.9)
                                                : Color.white.opacity(0.08)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if selectedExpectedOutputs.contains(.custom) {
                        textInputField(
                            isChinese ? "请输入自定义产出" : "Enter custom output",
                            text: $customExpectedOutputText
                        )
                    }
                }
            }

            sectionCard {
                formField(isChinese ? "学生起点与关注点（可选）" : "Student Baseline Notes (Optional)") {
                    multilineTextInput(
                        text: $draft.studentSupportNotes,
                        minHeight: 96,
                        placeholder: isChinese
                            ? "例如：班级基础中等；实验环节需加强安全提醒。"
                            : "e.g. Moderate baseline; add stronger safety reminders in lab activities."
                    )
                }
            }
        }
    }

    private var modelInputsPage: some View {
        pageContainer {
            sectionCard {
                formField(isChinese ? "课堂风格" : "Teaching Style", required: true) {
                    VStack(spacing: 8) {
                        ForEach(TeachingStyleMode.allCases, id: \.rawValue) { style in
                            Button {
                                draft.teachingStyle = style
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: draft.teachingStyle == style ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(draft.teachingStyle == style ? .cyan : .secondary)
                                    Text(teachingStyleTitle(style))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(
                                            draft.teachingStyle == style
                                            ? Color.cyan.opacity(0.14)
                                            : Color.white.opacity(0.05)
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(
                                            draft.teachingStyle == style
                                            ? Color.cyan.opacity(0.6)
                                            : Color.white.opacity(0.16),
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                formField(isChinese ? "过程性检查强度" : "Formative Check Intensity", required: true) {
                    Picker("", selection: $draft.formativeCheckIntensity) {
                        ForEach(FormativeCheckIntensity.allCases, id: \.rawValue) { value in
                            Text(formativeCheckTitle(value)).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(
                        isOn: $draft.emphasizeInquiryExperiment,
                        label: {
                            Text(isChinese ? "强调探究 / 实验" : "Emphasize inquiry / experiment")
                                .font(.subheadline)
                        }
                    )

                    Toggle(
                        isOn: $draft.emphasizeExperienceReflection,
                        label: {
                            Text(isChinese ? "强调体验-反思-再实践" : "Emphasize experience-reflection-practice")
                                .font(.subheadline)
                        }
                    )

                    Toggle(
                        isOn: $draft.requireStructuredFlow,
                        label: {
                            Text(isChinese ? "需要结构化流程（环环相扣）" : "Require a tightly-structured sequence")
                                .font(.subheadline)
                        }
                    )
                }
            }
        }
    }

    private var modelRecommendPage: some View {
        pageContainer {
            sectionCard {
                formField(S("course.recommendedModels"), required: true) {
                    if recommended.isEmpty {
                        Text(S("course.recommended.empty"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(recommended) { rule in
                            modelRow(rule: rule, recommended: true, showDetails: false)
                        }
                    }

                    Button {
                        showAllModelsInline.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Text(S("course.allModels"))
                            Image(systemName: showAllModelsInline ? "chevron.down" : "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.cyan)

                    if showAllModelsInline {
                        VStack(spacing: 10) {
                            ForEach(modelRules) { rule in
                                modelRow(rule: rule, recommended: false, showDetails: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private var teamStudentsPage: some View {
        pageContainer {
            sectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        HStack(spacing: 4) {
                            Text(S("course.section.teachingTeam"))
                                .font(.subheadline.weight(.semibold))
                            Text("*")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.orange)
                        }
                        .foregroundStyle(.secondary)

                        Spacer(minLength: 0)

                        Button {
                            teacherRoleRows.append(TeacherRoleRow(roleType: .assistant))
                        } label: {
                            Label(isChinese ? "添加" : "Add", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    roleDivisionTable
                }

                HStack(spacing: 14) {
                    roleCountPill(
                        title: S("course.team.leadCount"),
                        count: teacherRoleRows.filter { $0.roleType == .lead }.count
                    )
                    roleCountPill(
                        title: S("course.team.assistantCount"),
                        count: teacherRoleRows.filter { $0.roleType == .assistant }.count
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            sectionCard {
                formField(isChinese ? "学生名单（可选）" : "Student Roster (Optional)") {
                    studentRosterTable

                    HStack(spacing: 10) {
                        Button {
                            studentRows.append(StudentRosterRow())
                        } label: {
                            Label(isChinese ? "添加学生" : "Add Student", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            showingStudentCSVImporter = true
                        } label: {
                            Label(isChinese ? "导入 CSV" : "Import CSV", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)

                        Spacer(minLength: 0)
                    }
                }
            }

            sectionCard {
                formField(S("course.resourceConstraints")) {
                    multilineTextInput(
                        text: $draft.resourceConstraints,
                        minHeight: 96,
                        placeholder: isChinese ? "例如：实验器材有限，需分组轮换" : "e.g. Limited lab devices, use group rotation."
                    )
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(S("course.prev")) {
                goPrev()
            }
            .disabled(page == pages.first)

            Spacer()

            if page == pages.last {
                if let onSaveRoster {
                    Button(isChinese ? "保存名单" : "Save Roster") {
                        onSaveRoster(draft.studentRosterText)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(S("action.create"), action: onCreate)
                        .disabled(!draft.isValid || !isTeacherTeamValid)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Button(S("course.next")) {
                    goNext()
                }
                .disabled(!canGoNext)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(height: 1),
            alignment: .top
        )
    }

    @ViewBuilder
    private func modelRow(rule: EduModelRule, recommended: Bool, showDetails: Bool) -> some View {
        Button {
            draft.modelID = rule.id
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: draft.modelID == rule.id ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(draft.modelID == rule.id ? .cyan : .secondary)
                    .font(.callout.weight(.semibold))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(rule.displayName(isChinese: isChinese))
                            .font(.subheadline.weight(.semibold))
                        if recommended {
                            Text(S("course.recommended"))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.cyan.opacity(0.22))
                                .clipShape(Capsule())
                        }
                    }
                    Text(rule.displayDescription(isChinese: isChinese))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if showDetails {
                        VStack(alignment: .leading, spacing: 4) {
                            modelDetailRow(
                                title: isChinese ? "模板重点" : "Template Focus",
                                value: rule.templateFocus(isChinese: isChinese)
                            )
                            modelDetailRow(
                                title: isChinese ? "适用学段" : "Best For Grades",
                                value: localizedHints(rule.gradeHints, category: .grade).joined(separator: " / ")
                            )
                            modelDetailRow(
                                title: isChinese ? "适用学科" : "Best For Subjects",
                                value: localizedHints(rule.subjectHints, category: .subject).joined(separator: " / ")
                            )
                            modelDetailRow(
                                title: isChinese ? "适用场景" : "Best For Scenarios",
                                value: localizedHints(rule.scenarioHints, category: .scenario).joined(separator: " / ")
                            )
                            modelDetailRow(
                                title: isChinese ? "推荐 Toolkit" : "Recommended Toolkit",
                                value: recommendedToolkitNames(for: rule).joined(separator: " / ")
                            )
                        }
                        .padding(.top, 4)
                    }
                }

                Spacer(minLength: 8)

                modelThumbnail(ruleID: rule.id, isSelected: draft.modelID == rule.id)
                    .frame(width: 156, height: 86)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        draft.modelID == rule.id
                            ? Color.cyan.opacity(0.16)
                            : Color.white.opacity(0.05)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        draft.modelID == rule.id
                            ? Color.cyan.opacity(0.62)
                            : Color.white.opacity(0.16),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func modelDetailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(title):")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "-" : value)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func modelThumbnail(ruleID: String, isSelected: Bool) -> some View {
        let rawNodes = modelThumbnailNodes(for: ruleID)
        let nodes = rawNodes.map { point in
            CGPoint(
                x: 0.12 + point.x * 0.76,
                y: 0.14 + point.y * 0.72
            )
        }
        let edges = modelThumbnailEdges(for: ruleID)

        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let nodeWidth: CGFloat = 18
            let nodeHeight: CGFloat = 10

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                        ? Color.cyan.opacity(0.14)
                        : Color.white.opacity(0.03)
                    )

                ForEach(Array(edges.enumerated()), id: \.offset) { _, edge in
                    let from = nodes[edge.0]
                    let to = nodes[edge.1]

                    Path { path in
                        path.move(to: CGPoint(x: from.x * width, y: from.y * height))
                        path.addLine(to: CGPoint(x: to.x * width, y: to.y * height))
                    }
                    .stroke(Color.white.opacity(0.26), lineWidth: 1)
                }

                ForEach(Array(nodes.enumerated()), id: \.offset) { index, point in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(index == 0 ? Color.orange.opacity(0.95) : Color.cyan.opacity(0.88))
                        .frame(width: nodeWidth, height: nodeHeight)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color.black.opacity(0.15), lineWidth: 0.5)
                        )
                        .position(x: point.x * width, y: point.y * height)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected
                        ? Color.cyan.opacity(0.55)
                        : Color.white.opacity(0.14),
                        lineWidth: 1
                    )
            )
        }
    }

    private func modelThumbnailNodes(for ruleID: String) -> [CGPoint] {
        switch ruleID {
        case "ubd":
            return [
                CGPoint(x: 0.12, y: 0.22), CGPoint(x: 0.31, y: 0.22), CGPoint(x: 0.50, y: 0.22),
                CGPoint(x: 0.69, y: 0.66), CGPoint(x: 0.88, y: 0.66)
            ]
        case "fivee":
            return [
                CGPoint(x: 0.08, y: 0.52), CGPoint(x: 0.30, y: 0.22), CGPoint(x: 0.50, y: 0.54),
                CGPoint(x: 0.70, y: 0.22), CGPoint(x: 0.92, y: 0.52)
            ]
        case "kolb":
            return [
                CGPoint(x: 0.24, y: 0.18), CGPoint(x: 0.74, y: 0.18),
                CGPoint(x: 0.74, y: 0.82), CGPoint(x: 0.24, y: 0.82)
            ]
        case "boppps":
            return [
                CGPoint(x: 0.08, y: 0.24), CGPoint(x: 0.28, y: 0.24), CGPoint(x: 0.48, y: 0.24),
                CGPoint(x: 0.48, y: 0.76), CGPoint(x: 0.68, y: 0.76), CGPoint(x: 0.88, y: 0.76)
            ]
        case "gagne9":
            return [
                CGPoint(x: 0.08, y: 0.26), CGPoint(x: 0.24, y: 0.26), CGPoint(x: 0.40, y: 0.26),
                CGPoint(x: 0.56, y: 0.26), CGPoint(x: 0.72, y: 0.26), CGPoint(x: 0.88, y: 0.26),
                CGPoint(x: 0.88, y: 0.72), CGPoint(x: 0.72, y: 0.72), CGPoint(x: 0.56, y: 0.72)
            ]
        default:
            return [
                CGPoint(x: 0.14, y: 0.5), CGPoint(x: 0.38, y: 0.26), CGPoint(x: 0.62, y: 0.74), CGPoint(x: 0.86, y: 0.45)
            ]
        }
    }

    private func modelThumbnailEdges(for ruleID: String) -> [(Int, Int)] {
        switch ruleID {
        case "kolb":
            return [(0, 1), (1, 2), (2, 3), (3, 0)]
        case "gagne9":
            return [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6), (6, 7), (7, 8)]
        default:
            let count = modelThumbnailNodes(for: ruleID).count
            guard count > 1 else { return [] }
            return (0..<(count - 1)).map { ($0, $0 + 1) }
        }
    }

    private func recommendedToolkitNames(for rule: EduModelRule) -> [String] {
        let names = rule.toolkitPresetIDs.compactMap { toolkitPresetLookup[$0]?.title(isChinese: isChinese) }
        if names.isEmpty { return [] }
        return Array(NSOrderedSet(array: names)) as? [String] ?? names
    }

    private enum ModelHintCategory {
        case grade
        case subject
        case scenario
    }

    private func localizedHints(_ hints: [String], category: ModelHintCategory) -> [String] {
        var values: [String] = []
        for raw in hints {
            let mapped = localizedHint(raw, category: category)
            if !mapped.isEmpty, !values.contains(mapped) {
                values.append(mapped)
            }
        }
        return values
    }

    private func localizedHint(_ raw: String, category: ModelHintCategory) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch category {
        case .grade:
            if isChinese {
                switch key {
                case "elementary", "小学": return "小学"
                case "middle", "初中": return "初中"
                case "high", "高中": return "高中"
                case "all", "全学段": return "全学段"
                default: return containsChinese(raw) ? raw : ""
                }
            } else {
                switch key {
                case "elementary", "小学": return "Elementary"
                case "middle", "初中": return "Middle School"
                case "high", "高中": return "High School"
                case "all", "全学段": return "All Grades"
                default: return containsChinese(raw) ? "" : raw.capitalized
                }
            }

        case .subject:
            if isChinese {
                switch key {
                case "science", "理": return "理科"
                case "math": return "数学"
                case "history": return "历史"
                case "language", "语文": return "语文"
                case "social": return "社会"
                case "lab": return "实验科学"
                case "physics": return "物理"
                case "chemistry": return "化学"
                case "project", "综合": return "项目/综合"
                case "文": return "文科"
                default: return containsChinese(raw) ? raw : ""
                }
            } else {
                switch key {
                case "science", "理": return "Science"
                case "math": return "Mathematics"
                case "history": return "History"
                case "language", "语文": return "Language Arts"
                case "social": return "Social Studies"
                case "lab": return "Lab Science"
                case "physics": return "Physics"
                case "chemistry": return "Chemistry"
                case "project", "综合": return "Project-Based"
                case "文": return "Humanities"
                default: return containsChinese(raw) ? "" : raw.capitalized
                }
            }

        case .scenario:
            if isChinese {
                switch key {
                case "formal": return "常规课堂"
                case "class", "课堂": return "课堂教学"
                case "workshop": return "工作坊"
                case "discussion", "研讨", "讨论": return "讨论研讨"
                case "lab", "实验": return "实验探究"
                case "project": return "项目任务"
                default: return containsChinese(raw) ? raw : ""
                }
            } else {
                switch key {
                case "formal": return "Formal Lesson"
                case "class", "课堂": return "Classroom Lesson"
                case "workshop": return "Workshop"
                case "discussion", "研讨", "讨论": return "Discussion"
                case "lab", "实验": return "Lab Investigation"
                case "project": return "Project Task"
                default: return containsChinese(raw) ? "" : raw.capitalized
                }
            }
        }
    }

    private func containsChinese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (scalar.value >= 0x4E00 && scalar.value <= 0x9FFF) ||
            (scalar.value >= 0x3400 && scalar.value <= 0x4DBF)
        }
    }

    @ViewBuilder
    private func pageContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(
        title: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title, !title.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let subtitle, !subtitle.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            content()
        }
    }

    @ViewBuilder
    private func formField<Content: View>(
        _ title: String,
        required: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if required {
                    Text("*")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.orange)
                }
            }
            .foregroundStyle(.secondary)

            content()
        }
    }

    @ViewBuilder
    private func textInputField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
            )
    }

    @ViewBuilder
    private func numberInputField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: digitsOnlyBinding(text))
            .keyboardType(.numberPad)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
            )
    }

    @ViewBuilder
    private func percentInputField(text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            TextField("0-100", text: digitsOnlyBinding(text, max: 100))
                .keyboardType(.numberPad)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("%")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func rangeBoundField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.body.weight(.semibold))

            Rectangle()
                .fill(Color.cyan.opacity(0.85))
                .frame(height: 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func multilineTextInput(
        text: Binding<String>,
        minHeight: CGFloat,
        placeholder: String
    ) -> some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(4...10)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: minHeight, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
                )
        } else {
            TextField(placeholder, text: text)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: minHeight, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var roleDivisionTable: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                roleDivisionHeaderText(isChinese ? "角色" : "Role")
                    .frame(width: 116, alignment: .leading)
                roleDivisionHeaderText(isChinese ? "老师" : "Teacher")
                    .frame(width: 110, alignment: .leading)
                roleDivisionHeaderText(isChinese ? "职责" : "Responsibility")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: 18)
            }

            ForEach(Array(teacherRoleRows.indices), id: \.self) { index in
                HStack(spacing: 8) {
                    CourseFormDropdown(
                        id: roleDropdownID(teacherRoleRows[index].id),
                        title: isChinese ? "角色" : "Role",
                        options: TeacherRoleType.allCases.map {
                            CourseFormDropdownOption(value: $0.rawValue, title: $0.title(isChinese: isChinese))
                        },
                        selection: roleSelectionBinding(for: teacherRoleRows[index].id),
                        isExpanded: Binding(
                            get: { expandedRoleRowID == teacherRoleRows[index].id },
                            set: { isOpen in
                                expandedRoleRowID = isOpen ? teacherRoleRows[index].id : nil
                                if isOpen {
                                    isSubjectDropdownExpanded = false
                                    expandedGoalRowID = nil
                                }
                            }
                        ),
                        textFont: .system(size: 13, weight: .regular)
                    )
                    .frame(width: 116, alignment: .leading)
                    .zIndex(expandedRoleRowID == teacherRoleRows[index].id ? 500 : 0)

                    TextField(
                        isChinese ? "姓名" : "Name",
                        text: Binding(
                            get: { teacherRoleRows[index].teacherName },
                            set: { teacherRoleRows[index].teacherName = $0 }
                        )
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(width: 110)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
                    )

                    TextField(
                        isChinese ? "负责内容" : "Responsibility",
                        text: Binding(
                            get: { teacherRoleRows[index].responsibility },
                            set: { teacherRoleRows[index].responsibility = $0 }
                        )
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
                    )

                    Button(role: .destructive) {
                        teacherRoleRows.remove(at: index)
                        if teacherRoleRows.isEmpty {
                            teacherRoleRows.append(TeacherRoleRow(roleType: .lead))
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 18)
                }
                .zIndex(expandedRoleRowID == teacherRoleRows[index].id ? 1200 : 0)
            }
        }
    }

    @ViewBuilder
    private func roleDivisionHeaderText(_ value: String) -> some View {
        Text(value)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func roleCountPill(title: String, count: Int) -> some View {
        Text("\(title): \(max(0, count))")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var studentRosterTable: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                roleDivisionHeaderText(isChinese ? "姓名" : "Name")
                    .frame(width: 130, alignment: .leading)
                roleDivisionHeaderText(isChinese ? "分组" : "Group")
                    .frame(width: 128, alignment: .leading)
                roleDivisionHeaderText(isChinese ? "年龄" : "Age")
                    .frame(width: 72, alignment: .leading)
                Color.clear.frame(width: 18)
            }

            ForEach(Array(studentRows.indices), id: \.self) { index in
                HStack(spacing: 8) {
                    TextField(
                        isChinese ? "学生姓名" : "Student Name",
                        text: Binding(
                            get: { studentRows[index].name },
                            set: { studentRows[index].name = $0 }
                        )
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(width: 130)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
                    )

                    studentGroupTagInput(
                        rowID: studentRows[index].id,
                        groupText: studentRows[index].group,
                        width: 128
                    )

                    TextField(
                        isChinese ? "年龄" : "Age",
                        text: Binding(
                            get: { studentRows[index].ageText },
                            set: { studentRows[index].ageText = String($0.filter(\.isNumber)) }
                        )
                    )
                    .keyboardType(.numberPad)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(width: 72)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
                    )

                    Button(role: .destructive) {
                        studentRows.remove(at: index)
                        if studentRows.isEmpty {
                            studentRows.append(StudentRosterRow())
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 18)
                }
                .zIndex(expandedStudentGroupRowID == studentRows[index].id ? 1300 : 0)
            }
        }
    }

    @ViewBuilder
    private func studentGroupTagInput(
        rowID: UUID,
        groupText: String,
        width: CGFloat
    ) -> some View {
        let normalizedGroup = groupText.trimmingCharacters(in: .whitespacesAndNewlines)
        let suggestions = suggestedStudentGroupTags(for: rowID)
        let isExpanded = expandedStudentGroupRowID == rowID

        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    expandedStudentGroupRowID = isExpanded ? nil : rowID
                    if !isExpanded {
                        isSubjectDropdownExpanded = false
                        expandedGoalRowID = nil
                        expandedRoleRowID = nil
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if normalizedGroup.isEmpty {
                        Text(isChinese ? "选择分组标签" : "Select tag")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(normalizedGroup)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.cyan.opacity(0.28))
                            )
                    }

                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .frame(width: width, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isExpanded ? Color.cyan.opacity(0.55) : Color.cyan.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    if !suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(suggestions, id: \.self) { tag in
                                    Button {
                                        setStudentGroup(tag, for: rowID)
                                    } label: {
                                        Text(tag)
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 4)
                                            .background(
                                                Capsule()
                                                    .fill(Color.white.opacity(0.12))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }

                    HStack(spacing: 5) {
                        TextField(
                            isChinese ? "新标签" : "New tag",
                            text: pendingStudentGroupBinding(for: rowID)
                        )
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            commitPendingStudentGroup(rowID: rowID)
                        }

                        Button(isChinese ? "添加" : "Add") {
                            commitPendingStudentGroup(rowID: rowID)
                        }
                        .font(.caption2.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                    }
                }
                .frame(width: width, alignment: .leading)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private func pendingStudentGroupBinding(for rowID: UUID) -> Binding<String> {
        Binding(
            get: { pendingStudentGroupTextByRowID[rowID] ?? "" },
            set: { pendingStudentGroupTextByRowID[rowID] = $0 }
        )
    }

    private func commitPendingStudentGroup(rowID: UUID) {
        let pending = pendingStudentGroupTextByRowID[rowID] ?? ""
        let normalized = normalizedGroupTag(pending)
        guard !normalized.isEmpty else { return }
        setStudentGroup(normalized, for: rowID)
    }

    private func setStudentGroup(_ group: String, for rowID: UUID) {
        let normalized = normalizedGroupTag(group)
        guard let index = studentRows.firstIndex(where: { $0.id == rowID }) else { return }
        studentRows[index].group = normalized
        pendingStudentGroupTextByRowID[rowID] = ""
        withAnimation(.easeInOut(duration: 0.16)) {
            expandedStudentGroupRowID = nil
        }
    }

    private func suggestedStudentGroupTags(for rowID: UUID) -> [String] {
        var tags = studentRows
            .filter { $0.id != rowID }
            .map { normalizedGroupTag($0.group) }
            .filter { !$0.isEmpty }
        if tags.isEmpty {
            tags = isChinese ? ["A组", "B组", "C组"] : ["Group A", "Group B", "Group C"]
        }
        return Array(NSOrderedSet(array: tags)) as? [String] ?? tags
    }

    private func normalizedGroupTag(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "|", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func goPrev() {
        guard let currentIndex = pages.firstIndex(of: page), currentIndex > 0 else { return }
        closeAllDropdowns()
        page = pages[currentIndex - 1]
    }

    private func goNext() {
        guard canGoNext,
              let currentIndex = pages.firstIndex(of: page),
              currentIndex + 1 < pages.count else { return }
        closeAllDropdowns()
        page = pages[currentIndex + 1]
    }

    private func syncPresetSelectionWithSubject() {
        let subject = draft.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if subjectPresets.contains(subject) {
            selectedSubjectPreset = subject
        } else {
            selectedSubjectPreset = customSubjectTag
        }
    }

    private func goalPresetSelectionBinding(for rowID: UUID) -> Binding<String> {
        Binding(
            get: {
                goalRows.first(where: { $0.id == rowID })?.preset.rawValue
                ?? GoalPresetType.conceptUnderstanding.rawValue
            },
            set: { newValue in
                guard let preset = GoalPresetType(rawValue: newValue),
                      let index = goalRows.firstIndex(where: { $0.id == rowID }) else {
                    return
                }
                goalRows[index].preset = preset
            }
        )
    }

    private func initializeGoalRowsFromDraft() {
        guard goalRows.isEmpty else { return }

        let normalized = draft.goals
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalized.isEmpty else {
            goalRows = [GoalDraftRow(preset: .conceptUnderstanding)]
            syncDraftGoalsFromRows()
            return
        }

        goalRows = normalized.map { raw in
            let preset = inferGoalPreset(from: raw)
            return GoalDraftRow(
                preset: preset,
                detail: extractGoalDetail(from: raw, preset: preset)
            )
        }
        syncDraftGoalsFromRows()
    }

    private func syncDraftGoalsFromRows() {
        let goals = goalRows
            .map { row -> String in
                let detail = row.detail.trimmingCharacters(in: .whitespacesAndNewlines)
                if detail.isEmpty {
                    return row.preset == .custom ? "" : goalPresetTitle(row.preset)
                }
                if row.preset == .custom {
                    return detail
                }
                return "\(goalPresetTitle(row.preset)): \(detail)"
            }
            .filter { !$0.isEmpty }
        draft.goals = goals
    }

    private func initializeExpectedOutputsFromDraft() {
        var selected = Set(
            draft.expectedOutputIDs.compactMap { ExpectedOutputPreset(rawValue: $0) }
        )
        customExpectedOutputText = draft.expectedOutputCustomText
        if !customExpectedOutputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selected.insert(.custom)
        }
        selectedExpectedOutputs = selected
        syncDraftExpectedOutputs()
    }

    private func syncDraftExpectedOutputs() {
        draft.expectedOutputIDs = ExpectedOutputPreset.allCases
            .filter { $0 != .custom && selectedExpectedOutputs.contains($0) }
            .map(\.rawValue)
        let trimmedCustom = customExpectedOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.expectedOutputCustomText = selectedExpectedOutputs.contains(.custom) ? trimmedCustom : ""
    }

    private func initializeStudentRowsFromDraft() {
        guard studentRows.isEmpty else { return }
        let text = draft.studentRosterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            studentRows = [StudentRosterRow()]
            syncDraftStudentRosterSummary()
            return
        }

        var parsed: [StudentRosterRow] = []
        for line in text.split(separator: "\n") {
            let parts = line
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let name = parts.indices.contains(0) ? parts[0] : ""
            let group = parts.indices.contains(1) ? parts[1] : ""
            let age = parts.indices.contains(2) ? parts[2] : ""
            if !name.isEmpty || !group.isEmpty || !age.isEmpty {
                parsed.append(StudentRosterRow(name: name, group: group, ageText: age))
            }
        }
        studentRows = parsed.isEmpty ? [StudentRosterRow()] : parsed
        syncDraftStudentRosterSummary()
    }

    private func syncDraftStudentRosterSummary() {
        let normalized = studentRows
            .map {
                StudentRosterRow(
                    id: $0.id,
                    name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    group: $0.group.trimmingCharacters(in: .whitespacesAndNewlines),
                    ageText: $0.ageText.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.name.isEmpty || !$0.group.isEmpty || !$0.ageText.isEmpty }

        draft.studentRosterText = normalized.map { row in
            "\(row.name)|\(row.group)|\(row.ageText)"
        }.joined(separator: "\n")
    }

    private func handleStudentCSVImport(_ result: Result<URL, any Error>) {
        guard case .success(let url) = result else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url) else { return }
        let text =
            String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .unicode)
            ?? String(data: data, encoding: .ascii)
        guard let text else { return }

        let parsedRows = parseStudentCSVRows(text)
        guard !parsedRows.isEmpty else { return }
        studentRows = parsedRows
    }

    private func parseStudentCSVRows(_ raw: String) -> [StudentRosterRow] {
        let allLines = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !allLines.isEmpty else { return [] }

        let delimiter: Character = allLines.first?.contains("\t") == true ? "\t" : ","
        let parsed = allLines.map { parseCSVLine($0, delimiter: delimiter) }
        guard !parsed.isEmpty else { return [] }

        let headerTokens = parsed[0].map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        let hasHeader = headerTokens.contains { token in
            token.contains("name") || token.contains("student") || token.contains("姓名")
            || token.contains("group") || token.contains("组")
            || token.contains("age") || token.contains("年龄")
        }

        let rows = hasHeader ? Array(parsed.dropFirst()) : parsed
        guard !rows.isEmpty else { return [] }

        func indexFor(_ candidates: [String]) -> Int? {
            for candidate in candidates {
                if let idx = headerTokens.firstIndex(where: { $0.contains(candidate) }) {
                    return idx
                }
            }
            return nil
        }

        let nameIndex = hasHeader ? (indexFor(["name", "student", "姓名", "学生"]) ?? 0) : 0
        let groupIndex = hasHeader ? (indexFor(["group", "team", "组"]) ?? 1) : 1
        let ageIndex = hasHeader ? (indexFor(["age", "年龄"]) ?? 2) : 2

        return rows.compactMap { columns in
            func value(at index: Int) -> String {
                guard columns.indices.contains(index) else { return "" }
                return columns[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let name = value(at: nameIndex)
            let group = value(at: groupIndex)
            let age = String(value(at: ageIndex).filter(\.isNumber))

            if name.isEmpty && group.isEmpty && age.isEmpty {
                return nil
            }
            return StudentRosterRow(name: name, group: group, ageText: age)
        }
    }

    private func parseCSVLine(_ line: String, delimiter: Character) -> [String] {
        var values: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()

        while let char = iterator.next() {
            if char == "\"" {
                if inQuotes {
                    if let next = iterator.next() {
                        if next == "\"" {
                            current.append("\"")
                        } else {
                            inQuotes = false
                            if next == delimiter {
                                values.append(current)
                                current = ""
                            } else {
                                current.append(next)
                            }
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
                continue
            }

            if char == delimiter && !inQuotes {
                values.append(current)
                current = ""
                continue
            }

            current.append(char)
        }
        values.append(current)
        return values
    }

    private func inferGoalPreset(from text: String) -> GoalPresetType {
        let normalized = text.lowercased()
        if normalized.contains("概念") || normalized.contains("understand") || normalized.contains("concept") {
            return .conceptUnderstanding
        }
        if normalized.contains("迁移") || normalized.contains("应用") || normalized.contains("transfer") || normalized.contains("apply") {
            return .applicationTransfer
        }
        if normalized.contains("探究") || normalized.contains("推理") || normalized.contains("inquiry") || normalized.contains("reason") || normalized.contains("experiment") {
            return .inquiryReasoning
        }
        if normalized.contains("过程") || normalized.contains("技能") || normalized.contains("process") || normalized.contains("skill") {
            return .processSkill
        }
        if normalized.contains("协作") || normalized.contains("沟通") || normalized.contains("表达") || normalized.contains("communication") || normalized.contains("collaboration") {
            return .collaborationCommunication
        }
        if normalized.contains("反思") || normalized.contains("元认知") || normalized.contains("reflection") || normalized.contains("metacognition") {
            return .reflectionMetacognition
        }
        return .custom
    }

    private func extractGoalDetail(from text: String, preset: GoalPresetType) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in ["：", ":"] {
            if let range = trimmed.range(of: separator) {
                let lhs = trimmed[..<range.lowerBound].lowercased()
                let rhs = trimmed[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if lhs.contains(goalPresetTitle(preset).lowercased()) && !rhs.isEmpty {
                    return rhs
                }
            }
        }
        return trimmed
    }

    private func initializeTeacherRoleRowsFromDraft() {
        guard teacherRoleRows.isEmpty else { return }
        let trimmedPlan = draft.teacherRolePlan.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPlan.isEmpty else {
            teacherRoleRows = [TeacherRoleRow(roleType: .lead)]
            syncDraftFromTeacherRoleRows()
            return
        }

        var parsedRows: [TeacherRoleRow] = []
        for line in trimmedPlan.split(separator: "\n") {
            let parts = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count >= 3 {
                let rolePart = parts[0].lowercased()
                let roleType: TeacherRoleType = (rolePart.contains("lead") || rolePart.contains("主讲")) ? .lead : .assistant
                parsedRows.append(
                    TeacherRoleRow(
                        roleType: roleType,
                        teacherName: parts[1],
                        responsibility: parts[2...].joined(separator: " | ")
                    )
                )
            }
        }

        if parsedRows.isEmpty {
            parsedRows = [TeacherRoleRow(roleType: .lead, teacherName: "", responsibility: trimmedPlan)]
        }
        teacherRoleRows = parsedRows
        syncDraftFromTeacherRoleRows()
    }

    private func syncDraftFromTeacherRoleRows() {
        let rows = teacherRoleRows
            .map { row in
                TeacherRoleRow(
                    id: row.id,
                    roleType: row.roleType,
                    teacherName: row.teacherName.trimmingCharacters(in: .whitespacesAndNewlines),
                    responsibility: row.responsibility.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.teacherName.isEmpty || !$0.responsibility.isEmpty }

        let leadCount = rows.filter { $0.roleType == .lead }.count
        let assistantCount = rows.filter { $0.roleType == .assistant }.count

        draft.leadTeacherCountText = String(max(1, leadCount))
        draft.assistantTeacherCountText = String(max(0, assistantCount))

        draft.teacherRolePlan = rows.map { row in
            let role = row.roleType.title(isChinese: isChinese)
            let name = row.teacherName
            let duty = row.responsibility
            return "\(role) | \(name) | \(duty)"
        }.joined(separator: "\n")
    }

    private func roleSelectionBinding(for rowID: UUID) -> Binding<String> {
        Binding(
            get: {
                teacherRoleRows.first(where: { $0.id == rowID })?.roleType.rawValue
                ?? TeacherRoleType.assistant.rawValue
            },
            set: { newValue in
                guard let role = TeacherRoleType(rawValue: newValue),
                      let index = teacherRoleRows.firstIndex(where: { $0.id == rowID }) else {
                    return
                }
                teacherRoleRows[index].roleType = role
            }
        )
    }

    private func closeAllDropdowns() {
        isSubjectDropdownExpanded = false
        expandedGoalRowID = nil
        expandedRoleRowID = nil
        expandedStudentGroupRowID = nil
    }

    @ViewBuilder
    private func globalDropdownOverlay(
        anchors: [String: Anchor<CGRect>]
    ) -> some View {
        GeometryReader { proxy in
            if let payload = activeDropdownPayload,
               let anchor = anchors[payload.id] {
                let sourceFrame = proxy[anchor]
                let rowHeight: CGFloat = 40
                let contentHeight = rowHeight * CGFloat(max(1, payload.options.count))
                let maxHeight = min(contentHeight, proxy.size.height * 0.5)
                let spacing: CGFloat = 8
                let verticalPadding: CGFloat = 12
                let sidePadding: CGFloat = 12

                let availableBelow = max(0, proxy.size.height - sourceFrame.maxY - spacing - verticalPadding)
                let availableAbove = max(0, sourceFrame.minY - spacing - verticalPadding)
                let preferAbove = availableBelow < min(maxHeight, rowHeight * 2) && availableAbove > availableBelow
                let panelHeight = max(
                    rowHeight,
                    min(maxHeight, preferAbove ? availableAbove : availableBelow)
                )

                let requestedWidth = max(sourceFrame.width, payload.panelWidth ?? sourceFrame.width)
                let panelWidth = min(requestedWidth, proxy.size.width - sidePadding * 2)
                let minCenterX = panelWidth / 2 + sidePadding
                let maxCenterX = proxy.size.width - panelWidth / 2 - sidePadding
                let centerX = min(max(sourceFrame.midX, minCenterX), maxCenterX)
                let centerY = preferAbove
                    ? sourceFrame.minY - spacing - panelHeight / 2
                    : sourceFrame.maxY + spacing + panelHeight / 2

                ZStack {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture {
                            closeAllDropdowns()
                        }

                    CourseFormDropdownPanel(
                        options: payload.options,
                        selection: payload.selection,
                        textFont: payload.textFont,
                        maxHeight: panelHeight
                    ) {
                        closeAllDropdowns()
                    }
                    .frame(width: panelWidth, height: panelHeight)
                    .position(x: centerX, y: centerY)
                }
                .zIndex(50_000)
            }
        }
        .allowsHitTesting(activeDropdownPayload != nil)
    }

    private func S(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    private var pageIndicatorText: String {
        let format = S("course.pageIndicator")
        if format.contains("%") {
            return String(format: format, pageIndex + 1, pages.count)
        }
        return "\(pageIndex + 1) / \(pages.count)"
    }

    private func digitsOnlyBinding(_ text: Binding<String>, max: Int? = nil) -> Binding<String> {
        Binding(
            get: { text.wrappedValue },
            set: { newValue in
                var filtered = String(newValue.filter(\.isNumber))
                if let max, let value = Int(filtered), value > max {
                    filtered = String(max)
                }
                text.wrappedValue = filtered
            }
        )
    }
}

private struct CourseFormDropdownOption: Identifiable, Hashable {
    let value: String
    let title: String

    var id: String { value }
}

private struct CourseDropdownFieldAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [String: Anchor<CGRect>],
        nextValue: () -> [String: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct CourseFormDropdown: View {
    let id: String
    let title: String
    let options: [CourseFormDropdownOption]
    @Binding var selection: String
    @Binding var isExpanded: Bool
    var textFont: Font = .subheadline

    private var selectedTitle: String {
        if let matched = options.first(where: { $0.value == selection }) {
            return matched.title
        }
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? title : trimmed
    }

    private var rowHeight: CGFloat {
        40
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, macOS 26.0, *) {
                Button {
                    isExpanded.toggle()
                } label: {
                    triggerLabel
                }
                .buttonStyle(.glass)
            } else {
                Button {
                    isExpanded.toggle()
                } label: {
                    triggerLabel
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .anchorPreference(key: CourseDropdownFieldAnchorKey.self, value: .bounds) {
            [id: $0]
        }
        .zIndex(isExpanded ? 3000 : 0)
    }

    private var triggerLabel: some View {
        HStack(spacing: 8) {
            Text(selectedTitle)
                .font(textFont)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .frame(height: rowHeight)
    }
}

private struct CourseFormDropdownPanel: View {
    let options: [CourseFormDropdownOption]
    @Binding var selection: String
    let textFont: Font
    let maxHeight: CGFloat
    let onSelect: () -> Void

    private var rowHeight: CGFloat { 40 }
    private var panelCornerRadius: CGFloat { 12 }

    private func optionRow(for option: CourseFormDropdownOption) -> some View {
        HStack(spacing: 8) {
            Text(option.title)
                .font(textFont)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            if selection == option.value {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.cyan)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .frame(height: rowHeight)
        .background(
            selection == option.value
            ? Color.cyan.opacity(0.16)
            : Color.clear
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(options) { option in
                    Button {
                        selection = option.value
                        onSelect()
                    } label: {
                        optionRow(for: option)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: maxHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .compositingGroup()
    }

    @ViewBuilder
    private var panelBackground: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            ZStack {
                RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.95)
                Color.clear
                    .glassEffect(
                        .regular,
                        in: RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                    )
            }
        } else {
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}
