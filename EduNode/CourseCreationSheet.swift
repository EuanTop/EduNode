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

@MainActor
struct CourseCreationSheet: View {
    @Binding var draft: CourseCreationDraft
    let modelRules: [EduModelRule]
    let onCancel: () -> Void
    let onCreate: () -> Void

    @State private var page: CourseFormPage = .basics
    @State private var selectedSubjectPreset = "__custom__"
    @State private var newGoalText = ""
    @State private var showAllModelsSheet = false

    private let customSubjectTag = "__custom__"

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

    private var recommended: [EduModelRule] {
        EduPlanning.recommendedModels(for: draft, rules: modelRules)
    }

    private var pages: [CourseFormPage] {
        CourseFormPage.allCases
    }

    private var pageIndex: Int {
        pages.firstIndex(of: page) ?? 0
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
            VStack(spacing: 10) {
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

                footer
            }
            .navigationTitle(S("course.createTitle"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(S("action.cancel"), action: onCancel)
                }
            }
            .sheet(isPresented: $showAllModelsSheet) {
                allModelsSheet
            }
            .onAppear {
                if draft.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let first = subjectPresets.first {
                    draft.subject = first
                }
                syncPresetSelectionWithSubject()

                if draft.modelID.isEmpty, let firstRecommended = recommended.first {
                    draft.modelID = firstRecommended.id
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(pageIndicatorText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(page.title(S))
                .font(.headline)

            ProgressView(value: Double(pageIndex + 1), total: Double(pages.count))
                .tint(.cyan)
                .padding(.horizontal, 20)
        }
        .padding(.top, 8)
    }

    private var basicsPage: some View {
        Form {
            Section(S("course.section.required")) {
                labeledTextRow(S("course.name"), text: $draft.courseName)

                HStack(spacing: 12) {
                    Picker("", selection: $draft.gradeInputMode) {
                        Text(S("course.gradeMode.gradeRange")).tag(GradeInputMode.grade)
                        Text(S("course.gradeMode.ageRange")).tag(GradeInputMode.age)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 250)

                    HStack(spacing: 8) {
                        TextField(
                            draft.gradeInputMode == .grade ? S("course.gradeMin") : S("course.ageMin"),
                            text: digitsOnlyBinding($draft.gradeMinText)
                        )
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 88)

                        Text("-")
                            .foregroundStyle(.secondary)

                        TextField(
                            draft.gradeInputMode == .grade ? S("course.gradeMax") : S("course.ageMax"),
                            text: digitsOnlyBinding($draft.gradeMaxText)
                        )
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 88)
                    }
                }

                LabeledContent(S("course.subject")) {
                    Picker("", selection: $selectedSubjectPreset) {
                        ForEach(subjectPresets, id: \.self) { item in
                            Text(item).tag(item)
                        }
                        Text(S("course.subjectCustom")).tag(customSubjectTag)
                    }
                    .labelsHidden()
                    .onChange(of: selectedSubjectPreset) { _, newValue in
                        if newValue != customSubjectTag {
                            draft.subject = newValue
                        }
                    }
                }

                if selectedSubjectPreset == customSubjectTag {
                    labeledTextRow(S("course.subjectCustomInput"), text: $draft.subject)
                }

                labeledNumberRow(S("course.duration"), text: $draft.lessonDurationMinutesText)
                labeledNumberRow(S("course.studentCount"), text: $draft.studentCountText)
                labeledTextRow(S("course.periodRange"), text: $draft.periodRange)
            }
        }
    }

    private var studentsGoalsPage: some View {
        Form {
            Section(S("course.section.students")) {
                labeledPercentRow(S("course.studentPriorAssessmentScore"), text: $draft.priorAssessmentScoreText)
                labeledPercentRow(S("course.studentAssignmentCompletion"), text: $draft.assignmentCompletionRateText)
                labeledNumberRow(S("course.studentSupportNeedCount"), text: $draft.supportNeedCountText)

                VStack(alignment: .leading, spacing: 8) {
                    Text(S("course.studentSupport"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    multilineTextInput(text: $draft.studentSupportNotes, minHeight: 100)
                }

                Button(S("course.studentImportTable")) {
                }
                .disabled(true)
            }

            Section(S("course.section.goals")) {
                if draft.goals.isEmpty {
                    Text(S("course.goals.empty"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(draft.goals.enumerated()), id: \.offset) { index, goal in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .foregroundStyle(.secondary)
                            Text(goal)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button(role: .destructive) {
                                draft.goals.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField(S("course.goals.placeholder"), text: $newGoalText)
                    Button(S("course.goals.add")) {
                        addGoal()
                    }
                    .disabled(newGoalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var modelPage: some View {
        Form {
            Section(S("course.recommendedModels")) {
                if recommended.isEmpty {
                    Text(S("course.recommended.empty"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recommended) { rule in
                        modelRow(rule: rule, recommended: true)
                    }
                }
            }

            Section {
                Button {
                    showAllModelsSheet = true
                } label: {
                    HStack {
                        Text(S("course.allModelsAction"))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var teachingTeamPage: some View {
        Form {
            Section(S("course.section.teachingTeam")) {
                labeledNumberRow(S("course.team.leadCount"), text: $draft.leadTeacherCountText)
                labeledNumberRow(S("course.team.assistantCount"), text: $draft.assistantTeacherCountText)

                VStack(alignment: .leading, spacing: 8) {
                    Text(S("course.team.rolePlan"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    multilineTextInput(text: $draft.teacherRolePlan, minHeight: 110)
                }
            }

            Section(S("course.section.optional")) {
                labeledTextRow(S("course.resourceConstraints"), text: $draft.resourceConstraints)
            }
        }
    }

    private var allModelsSheet: some View {
        NavigationStack {
            List {
                ForEach(modelRules) { rule in
                    modelRow(rule: rule, recommended: false)
                }
            }
            .navigationTitle(S("course.allModels"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(S("action.close")) {
                        showAllModelsSheet = false
                    }
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
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func modelRow(rule: EduModelRule, recommended: Bool) -> some View {
        Button {
            draft.modelID = rule.id
            if !recommended {
                showAllModelsSheet = false
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: draft.modelID == rule.id ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(draft.modelID == rule.id ? .cyan : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(rule.displayName(isChinese: isChinese))
                            .font(.subheadline.weight(.semibold))
                        if recommended {
                            Text(S("course.recommended"))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.cyan.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                    Text(rule.displayDescription(isChinese: isChinese))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addGoal() {
        let trimmed = newGoalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draft.goals.append(trimmed)
        newGoalText = ""
    }

    private func goPrev() {
        guard let currentIndex = pages.firstIndex(of: page), currentIndex > 0 else { return }
        page = pages[currentIndex - 1]
    }

    private func goNext() {
        guard canGoNext,
              let currentIndex = pages.firstIndex(of: page),
              currentIndex + 1 < pages.count else { return }
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

    @ViewBuilder
    private func labeledTextRow(_ title: String, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField("", text: text)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func labeledNumberRow(_ title: String, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField("", text: digitsOnlyBinding(text))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func labeledPercentRow(_ title: String, text: Binding<String>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField("", text: digitsOnlyBinding(text, max: 100))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
                Text("%")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func multilineTextInput(text: Binding<String>, minHeight: CGFloat) -> some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            TextField("", text: text, axis: .vertical)
                .lineLimit(4...10)
                .padding(8)
                .frame(minHeight: minHeight, alignment: .topLeading)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            TextField("", text: text)
                .padding(8)
                .frame(minHeight: minHeight, alignment: .topLeading)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
