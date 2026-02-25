import SwiftUI

private enum CourseFormPage: Int, CaseIterable {
    case basics
    case studentsGoals
    case model
    case teachingTeam

    func title(_ S: (String) -> String) -> String {
        switch self {
        case .basics:
            return S("course.page.basics")
        case .studentsGoals:
            return S("course.page.studentsGoals")
        case .model:
            return S("course.page.model")
        case .teachingTeam:
            return S("course.page.teachingTeam")
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

@MainActor
struct CourseCreationSheet: View {
    @Binding var draft: CourseCreationDraft
    let modelRules: [EduModelRule]
    let onCancel: () -> Void
    let onCreate: () -> Void

    @State private var page: CourseFormPage = .basics
    @State private var selectedSubjectPreset = "__custom__"
    @State private var newGoalText = ""
    @State private var showAllModelsInline = false
    @State private var teacherRoleRows: [TeacherRoleRow] = []
    @State private var isSubjectDropdownExpanded = false
    @State private var expandedRoleRowID: UUID?

    private let customSubjectTag = "__custom__"
    private let subjectDropdownID = "course.subject.dropdown"

    private struct ActiveCourseDropdownPayload {
        let id: String
        let options: [CourseFormDropdownOption]
        let selection: Binding<String>
        let textFont: Font
    }

    private func roleDropdownID(_ rowID: UUID) -> String {
        "course.role.\(rowID.uuidString)"
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
        case .studentsGoals:
            return [
                HeaderArtItem(name: "tellurion", widthRatio: 3.10, xOffsetRatio: -0.30, yOffset: 12, rotation: -31, opacity: 0.28),
                HeaderArtItem(name: "book", widthRatio: 2.05, xOffsetRatio: 0.48, yOffset: 76, rotation: 25, opacity: 0.19)
            ]
        case .model:
            return [
                HeaderArtItem(name: "bulb", widthRatio: 3.16, xOffsetRatio: -0.31, yOffset: 10, rotation: -32, opacity: 0.30),
                HeaderArtItem(name: "chemistry", widthRatio: 2.08, xOffsetRatio: 0.48, yOffset: 78, rotation: 23, opacity: 0.20)
            ]
        case .teachingTeam:
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
                textFont: .subheadline
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
                textFont: .system(size: 13, weight: .regular)
            )
        }

        return nil
    }

    private var isAnyFormDropdownExpanded: Bool {
        isSubjectDropdownExpanded || expandedRoleRowID != nil
    }

    private var canGoNext: Bool {
        switch page {
        case .basics:
            return !draft.courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !draft.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            draft.lessonDurationMinutes > 0 &&
            draft.studentCount > 0 &&
            draft.normalizedGradeRange.1 >= draft.normalizedGradeRange.0

        case .studentsGoals:
            return !draft.goalsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        case .model:
            return !draft.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        case .teachingTeam:
            return draft.leadTeacherCount > 0
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                Group {
                    switch page {
                    case .basics:
                        basicsPage
                    case .studentsGoals:
                        studentsGoalsPage
                    case .model:
                        modelPage
                    case .teachingTeam:
                        teachingTeamPage
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
                if draft.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let first = subjectPresets.first {
                    draft.subject = first
                }
                syncPresetSelectionWithSubject()
                initializeTeacherRoleRowsFromDraft()

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
            .overlayPreferenceValue(CourseDropdownFieldAnchorKey.self) { anchors in
                globalDropdownOverlay(anchors: anchors)
            }
        }
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

                formField(S("course.notes")) {
                    textInputField(
                        isChinese ? "例如：器材有限，需分组轮换；需要双语关键词。" : "e.g. Limited equipment, rotate by groups; include bilingual keywords.",
                        text: $draft.periodRange
                    )
                }
            }
        }
    }

    private var studentsGoalsPage: some View {
        pageContainer {
            sectionCard(
                title: S("course.section.students"),
                subtitle: isChinese ? "填写教师可直接提供的班级信息即可。" : "Only fill teacher-friendly class information."
            ) {
                formField(isChinese ? "班级学情简述（可选）" : "Class Profile (Optional)") {
                    multilineTextInput(
                        text: $draft.studentSupportNotes,
                        minHeight: 110,
                        placeholder: isChinese ? "例如：整体基础中等，实验参与积极，个别学生需要更多操作指导。" : "e.g. Moderate baseline, active in experiments, a few students need extra hands-on guidance."
                    )
                }
            }

            sectionCard(
                title: S("course.section.goals"),
                subtitle: isChinese ? "至少 1 条目标，建议 2-4 条。" : "At least one goal is required. Recommended 2-4 goals."
            ) {
                if draft.goals.isEmpty {
                    Text(S("course.goals.empty"))
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(draft.goals.enumerated()), id: \.offset) { index, goal in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1).")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(goal)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button(role: .destructive) {
                                draft.goals.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                    }
                }

                HStack(spacing: 8) {
                    textInputField(
                        S("course.goals.placeholder"),
                        text: $newGoalText
                    )
                    .frame(maxWidth: .infinity)

                    Button(S("course.goals.add")) {
                        addGoal()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newGoalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var modelPage: some View {
        pageContainer {
            sectionCard(
                title: S("course.recommendedModels"),
                subtitle: isChinese ? "根据你已填写的信息推荐。" : "Recommended from your current course inputs."
            ) {
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

    private var teachingTeamPage: some View {
        pageContainer {
            sectionCard(
                title: S("course.section.teachingTeam"),
                subtitle: isChinese ? "用表格逐行填写每位老师及职责。" : "Use rows to assign each teacher and responsibility."
            ) {
                formField(isChinese ? "角色分工" : "Role Division", required: true) {
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

            sectionCard(
                title: S("course.section.optional"),
                subtitle: isChinese ? "可补充设备、空间、时间等限制条件。" : "Optional constraints: equipment, space, time, etc."
            ) {
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
                Button(S("action.create"), action: onCreate)
                    .disabled(!draft.isValid)
                    .buttonStyle(.borderedProminent)
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

                Spacer(minLength: 0)
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

            HStack {
                Button {
                    teacherRoleRows.append(TeacherRoleRow(roleType: .assistant))
                } label: {
                    Label(isChinese ? "添加一行" : "Add Row", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
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

    private func addGoal() {
        let trimmed = newGoalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draft.goals.append(trimmed)
        newGoalText = ""
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
            let name = row.teacherName.isEmpty ? (isChinese ? "未命名老师" : "Unnamed Teacher") : row.teacherName
            let duty = row.responsibility.isEmpty ? (isChinese ? "未填写职责" : "Responsibility not provided") : row.responsibility
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
        expandedRoleRowID = nil
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

                let minCenterX = sourceFrame.width / 2 + sidePadding
                let maxCenterX = proxy.size.width - sourceFrame.width / 2 - sidePadding
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
                    .frame(width: sourceFrame.width, height: panelHeight)
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
