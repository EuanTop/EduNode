import SwiftUI
import GNodeKit
import SwiftData

extension ContentView {
    @ViewBuilder
    func presentationTrackingPanel(
        file: GNodeWorkspaceFile,
        groups: [EduPresentationSlideGroup],
        topPadding: CGFloat,
        graphData: Data
    ) -> some View {
        if let summary = presentationTrackingSummary(file: file, groups: groups) {
            VStack {
                HStack {
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(summary.isChinese ? "课程追踪" : "Course Tracking")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("\(summary.currentPage)/\(summary.totalPages)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    BloomLevelChartView(
                        chips: summary.levelChips,
                        activeLevelIDs: summary.activeKnowledgeLevelIDs,
                        isChinese: summary.isChinese
                    )

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
                        presentationInlineEvaluationTable(
                            fileID: file.id,
                            summary: summary
                        )
                    }

                    if summary.currentPage == summary.totalPages, summary.totalPages > 0 {
                        Button {
                            finishPresentationCourse(
                                for: file,
                                graphData: graphData
                            )
                        } label: {
                            Text("Finish")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(Color.orange.opacity(0.82))
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .frame(maxWidth: 360, alignment: .leading)
                .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.22), radius: 8, y: 2)
                .padding(.trailing, 20)
                }
                .padding(.top, topPadding + 52)
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .top)
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    @ViewBuilder
    func presentationInlineEvaluationTable(
        fileID: UUID,
        summary: PresentationTrackingSummary
    ) -> some View {
        let signature = inlineEvaluationSignature(summary: summary)

        let tableContent = VStack(alignment: .leading, spacing: 10) {
            ForEach(summary.activeEvaluationNodes) { node in
                inlineEvaluationNodeSection(
                    fileID: fileID,
                    node: node,
                    studentRoster: summary.studentRoster,
                    isChinese: summary.isChinese
                )
            }
        }
        .padding(.vertical, 2)

        ViewThatFits(in: .vertical) {
            tableContent

            ScrollView(.vertical, showsIndicators: true) {
                tableContent
            }
            .frame(maxHeight: 260)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 2)
        .onAppear {
            ensureInlineEvaluationDefaults(fileID: fileID, summary: summary)
        }
        .onChange(of: signature) { _, _ in
            ensureInlineEvaluationDefaults(fileID: fileID, summary: summary)
        }
    }

    @ViewBuilder
    func inlineEvaluationNodeSection(
        fileID: UUID,
        node: EvaluationNodeDescriptor,
        studentRoster: [StudentRosterEntry],
        isChinese: Bool
    ) -> some View {
        let sequenceColumnWidth: CGFloat = 36
        let nameColumnWidth: CGFloat = 110
        let metricColumnWidth: CGFloat = 120

        VStack(alignment: .leading, spacing: 7) {
            Text(trackingEvaluationTitle(for: node.title, isChinese: isChinese))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

            if node.indicators.isEmpty {
                Text(isChinese ? "该 Evaluation 节点未配置指标。" : "This Evaluation node has no indicators.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(isChinese ? "序号" : "No.")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(width: sequenceColumnWidth, alignment: .center)

                            Text(isChinese ? "学生" : "Student")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(width: nameColumnWidth, alignment: .center)

                            ForEach(node.indicators) { indicator in
                                Text(indicator.name)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                                    .frame(width: metricColumnWidth, alignment: .center)
                            }
                        }

                        ForEach(studentRoster) { student in
                            HStack(spacing: 6) {
                                Text("\(student.sequence)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: sequenceColumnWidth, alignment: .center)

                                Text(studentNameLabel(student))
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                                    .frame(width: nameColumnWidth, alignment: .center)

                                ForEach(node.indicators) { indicator in
                                    let key = InlineEvaluationScoreKey(
                                        nodeID: node.id,
                                        indicatorID: indicator.id,
                                        studentName: student.name
                                    )
                                    switch indicator.kind {
                                    case .score:
                                        TextField(
                                            "0-5",
                                            text: inlineEvaluationScoreBinding(fileID: fileID, key: key)
                                        )
                                        .textFieldStyle(.plain)
                                        .keyboardType(.numberPad)
                                        .font(.caption2)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(Color(white: 0.22))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                                        )
                                        .frame(width: metricColumnWidth)
                                    case .completion:
                                        inlineEvaluationCompletionToggle(
                                            isSelected: inlineEvaluationCompletionValue(fileID: fileID, key: key)
                                        ) {
                                            let current = inlineEvaluationCompletionValue(fileID: fileID, key: key)
                                            setInlineEvaluationCompletionValue(fileID: fileID, key: key, value: !current)
                                        }
                                        .frame(width: metricColumnWidth, alignment: .center)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    @ViewBuilder
    func inlineEvaluationCompletionToggle(
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.green.opacity(0.9) : Color.clear)
                    .overlay(
                        Circle()
                            .stroke(
                                isSelected ? Color.green.opacity(0.95) : Color.white.opacity(0.45),
                                lineWidth: 1.8
                            )
                    )
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }

    func trackingEvaluationTitle(for rawTitle: String, isChinese: Bool) -> String {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()
        if normalized.contains("class performance evaluation")
            || normalized.contains("class performace evaluation")
            || normalized == "evaluation"
            || normalized.contains("课堂表现评价") {
            return isChinese ? "Evaluation 打分" : "Evaluation Scoring"
        }
        return trimmed.isEmpty
            ? (isChinese ? "Evaluation 打分" : "Evaluation Scoring")
            : trimmed
    }

    func studentNameLabel(_ student: StudentRosterEntry) -> String {
        let group = student.group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !group.isEmpty else { return student.name }
        return "\(student.name) [\(group)]"
    }

    func inlineEvaluationSignature(summary: PresentationTrackingSummary) -> String {
        let nodePart = summary.activeEvaluationNodes
            .map { node in
                let indicatorPart = node.indicators
                    .map { "\($0.id)#\($0.kind == .completion ? "c" : "s")" }
                    .joined(separator: ",")
                return "\(node.id.uuidString):\(indicatorPart)"
            }
            .joined(separator: "|")
        let studentPart = summary.studentNames.joined(separator: "|")
        return "\(nodePart)||\(studentPart)"
    }

    func ensureInlineEvaluationDefaults(
        fileID: UUID,
        summary: PresentationTrackingSummary
    ) {
        var scoreMap = inlineEvaluationScoreValuesByFile[fileID] ?? [:]
        var completionMap = inlineEvaluationCompletionValuesByFile[fileID] ?? [:]

        for node in summary.activeEvaluationNodes {
            for indicator in node.indicators {
                for studentName in summary.studentNames {
                    let key = InlineEvaluationScoreKey(
                        nodeID: node.id,
                        indicatorID: indicator.id,
                        studentName: studentName
                    )
                    switch indicator.kind {
                    case .score:
                        if scoreMap[key] == nil {
                            scoreMap[key] = "0"
                        }
                    case .completion:
                        if completionMap[key] == nil {
                            completionMap[key] = false
                        }
                    }
                }
            }
        }

        inlineEvaluationScoreValuesByFile[fileID] = scoreMap
        inlineEvaluationCompletionValuesByFile[fileID] = completionMap
    }

    func inlineEvaluationScoreBinding(
        fileID: UUID,
        key: InlineEvaluationScoreKey
    ) -> Binding<String> {
        Binding(
            get: {
                inlineEvaluationScoreValuesByFile[fileID]?[key] ?? "0"
            },
            set: { newValue in
                let normalized = normalizedInlineEvaluationScoreText(newValue)
                var map = inlineEvaluationScoreValuesByFile[fileID] ?? [:]
                map[key] = normalized
                inlineEvaluationScoreValuesByFile[fileID] = map
            }
        )
    }

    func normalizedInlineEvaluationScoreText(_ raw: String) -> String {
        let allowed = "0123456789"
        let filtered = String(raw.filter { allowed.contains($0) })
        guard !filtered.isEmpty else { return "0" }
        guard let number = Int(filtered) else { return "0" }
        let clamped = min(5, max(0, number))
        return String(clamped)
    }

    func inlineEvaluationCompletionValue(
        fileID: UUID,
        key: InlineEvaluationScoreKey
    ) -> Bool {
        inlineEvaluationCompletionValuesByFile[fileID]?[key] ?? false
    }

    func setInlineEvaluationCompletionValue(
        fileID: UUID,
        key: InlineEvaluationScoreKey,
        value: Bool
    ) {
        var map = inlineEvaluationCompletionValuesByFile[fileID] ?? [:]
        map[key] = value
        inlineEvaluationCompletionValuesByFile[fileID] = map
    }

    func presentationTrackingSummary(
        file: GNodeWorkspaceFile,
        groups: [EduPresentationSlideGroup]
    ) -> PresentationTrackingSummary? {
        guard !groups.isEmpty else { return nil }
        let index = selectedPresentationGroupIndex(fileID: file.id, groups: groups)
        let currentGroup = groups[index]
        let isChinese = isChineseUI()
        let studentRoster = parsedStudentRosterEntries(from: file.studentProfile)

        guard let document = try? decodeDocument(from: file.data) else {
            return PresentationTrackingSummary(
                currentPage: index + 1,
                totalPages: groups.count,
                levelChips: defaultKnowledgeLevelCountChips(),
                activeKnowledgeLevelIDs: [],
                activeEvaluationNodes: [],
                studentRoster: studentRoster,
                isChinese: isChinese
            )
        }

        let nodeByID = Dictionary(uniqueKeysWithValues: document.nodes.map { ($0.id, $0) })
        let stateByNodeID = Dictionary(uniqueKeysWithValues: document.canvasState.map { ($0.nodeID, $0) })
        let nodeTypeByID = Dictionary(uniqueKeysWithValues: document.nodes.map { ($0.id, $0.nodeType) })
        let currentLearningNodeIDs = Set(
            currentGroup.sourceSlides.compactMap { slide -> UUID? in
                guard let nodeType = nodeTypeByID[slide.id],
                      isTrackableLearningNodeType(nodeType) else {
                    return nil
                }
                return slide.id
            }
        )
        var directEvaluationInputPortIDsByNodeID: [UUID: Set<UUID>] = [:]
        for connection in document.connections {
            guard currentLearningNodeIDs.contains(connection.sourceNodeID) else { continue }
            guard nodeTypeByID[connection.targetNodeID] == EduNodeType.evaluation else { continue }
            directEvaluationInputPortIDsByNodeID[connection.targetNodeID, default: []].insert(connection.targetPortID)
        }

        let sortedEvaluationIDs = directEvaluationInputPortIDsByNodeID.keys.sorted { lhs, rhs in
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
            let connectedTargetPortIDs = directEvaluationInputPortIDsByNodeID[nodeID] ?? []
            return evaluationDescriptor(
                for: node,
                customName: customName,
                connectedTargetPortIDs: connectedTargetPortIDs
            )
        }
        let activeKnowledgeLevelIDs = activeKnowledgeLevels(
            in: currentGroup,
            nodeByID: nodeByID
        )

        return PresentationTrackingSummary(
            currentPage: index + 1,
            totalPages: groups.count,
            levelChips: knowledgeLevelCountChips(from: document),
            activeKnowledgeLevelIDs: activeKnowledgeLevelIDs,
            activeEvaluationNodes: evaluationDescriptors,
            studentRoster: studentRoster,
            isChinese: isChinese
        )
    }

    func selectedPresentationGroupIndex(
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

    func knowledgeLevelCountChips(from document: GNodeDocument) -> [KnowledgeLevelCountChip] {
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

    func activeKnowledgeLevels(
        in group: EduPresentationSlideGroup,
        nodeByID: [UUID: SerializableNode]
    ) -> Set<String> {
        var levels: Set<String> = []
        for slide in group.sourceSlides {
            guard slide.nodeType == EduNodeType.knowledge else { continue }
            if let node = nodeByID[slide.id],
               let levelID = canonicalKnowledgeLevelID(from: node.nodeData["level"] ?? slide.subtitle) {
                levels.insert(levelID)
                continue
            }
            if let fallback = canonicalKnowledgeLevelID(from: slide.subtitle) {
                levels.insert(fallback)
            }
        }
        return levels
    }

    func defaultKnowledgeLevelCountChips() -> [KnowledgeLevelCountChip] {
        [
            KnowledgeLevelCountChip(id: "remember", title: S("edu.knowledge.type.remember"), count: 0),
            KnowledgeLevelCountChip(id: "understand", title: S("edu.knowledge.type.understand"), count: 0),
            KnowledgeLevelCountChip(id: "apply", title: S("edu.knowledge.type.apply"), count: 0),
            KnowledgeLevelCountChip(id: "analyze", title: S("edu.knowledge.type.analyze"), count: 0),
            KnowledgeLevelCountChip(id: "evaluate", title: S("edu.knowledge.type.evaluate"), count: 0),
            KnowledgeLevelCountChip(id: "create", title: S("edu.knowledge.type.create"), count: 0)
        ]
    }

    struct BloomLevelChartView: View {
        let chips: [KnowledgeLevelCountChip]
        let activeLevelIDs: Set<String>
        let isChinese: Bool

        @State var tooltipIndex: Int?

        let barColors: [Color] = [
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
                    let centers: [CGFloat] = {
                        var runningX: CGFloat = 0
                        var value: [CGFloat] = []
                        for width in widths {
                            value.append(runningX + width / 2)
                            runningX += width + gap
                        }
                        return value
                    }()

                    VStack(alignment: .leading, spacing: 3) {
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
                                .onLongPressGesture(
                                    minimumDuration: 0.28,
                                    maximumDistance: 26
                                ) {
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        tooltipIndex = i
                                    }
                                }
                            }
                        }
                        .clipShape(Capsule())

                        HStack(spacing: gap) {
                            ForEach(Array(pairs.enumerated()), id: \.offset) { i, pair in
                                let (chip, color) = pair
                                let w = widths[i]
                                let isActive = activeLevelIDs.contains(chip.id)
                                ZStack {
                                    Circle()
                                        .fill(isActive ? color : color.opacity(chips[i].count > 0 ? 0.35 : 0.18))
                                        .frame(width: isActive ? 6 : 4, height: isActive ? 6 : 4)
                                }
                                .frame(width: w, height: 12)
                            }
                        }

                        HStack(spacing: gap) {
                            ForEach(Array(pairs.enumerated()), id: \.offset) { i, pair in
                                let (chip, color) = pair
                                let w = widths[i]
                                let isActive = activeLevelIDs.contains(chip.id)
                                Group {
                                    if isActive {
                                        Text(chip.title)
                                            .font(.system(size: 8, weight: .semibold))
                                            .foregroundStyle(color.opacity(0.95))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.45)
                                    } else {
                                        Text("")
                                    }
                                }
                                .frame(width: w, height: 10, alignment: .center)
                            }
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if let idx = tooltipIndex,
                           chips.indices.contains(idx),
                           barColors.indices.contains(idx),
                           centers.indices.contains(idx) {
                            let safeMaxX = max(20, (centers.last ?? geo.size.width) - 8)
                            let centerX = max(20, min(safeMaxX, centers[idx]))
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(barColors[idx])
                                    .frame(width: 5, height: 5)
                                Text(chips[idx].title)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                                Text("\(chips[idx].count)")
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .offset(x: centerX - 44, y: -24)
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        if tooltipIndex == idx {
                                            tooltipIndex = nil
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(height: 40)
            }
        }
    }

    func canonicalKnowledgeLevelID(from raw: String) -> String? {
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

    func isTrackableLearningNodeType(_ nodeType: String) -> Bool {
        if nodeType == EduNodeType.knowledge { return true }
        if EduNodeType.allToolkitTypes.contains(nodeType) { return true }
        return nodeType.hasPrefix("EduToolkit")
    }

    func evaluationDescriptor(
        for node: SerializableNode,
        customName: String?,
        connectedTargetPortIDs: Set<UUID>
    ) -> EvaluationNodeDescriptor {
        let custom = (customName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = custom.isEmpty ? node.attributes.name : custom
        let textFields = parseJSONStringDictionary(node.nodeData["evaluationTextFields"])
        let indicatorsRaw = textFields["evaluation_indicators"] ?? node.nodeData["evaluation_indicators"] ?? ""
        let parsedIndicators = parseEvaluationIndicators(
            from: indicatorsRaw,
            fallbackInputPorts: node.inputPorts
        )
        let indicators = filteredEvaluationIndicators(
            parsedIndicators: parsedIndicators,
            for: node,
            connectedTargetPortIDs: connectedTargetPortIDs
        )
        return EvaluationNodeDescriptor(
            id: node.id,
            title: title,
            indicators: indicators
        )
    }

    func filteredEvaluationIndicators(
        parsedIndicators: [EvaluationIndicatorDescriptor],
        for node: SerializableNode,
        connectedTargetPortIDs: Set<UUID>
    ) -> [EvaluationIndicatorDescriptor] {
        guard !connectedTargetPortIDs.isEmpty else {
            return parsedIndicators
        }

        let portIndexByID = Dictionary(
            uniqueKeysWithValues: node.inputPorts.enumerated().map { offset, port in
                (port.id, offset)
            }
        )
        let connectedIndices = connectedTargetPortIDs
            .compactMap { portIndexByID[$0] }
            .sorted()
        guard !connectedIndices.isEmpty else {
            return parsedIndicators
        }

        var filtered: [EvaluationIndicatorDescriptor] = []
        for (order, index) in connectedIndices.enumerated() {
            if parsedIndicators.indices.contains(index) {
                filtered.append(parsedIndicators[index])
                continue
            }

            let fallbackName: String
            if node.inputPorts.indices.contains(index) {
                let inputName = node.inputPorts[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
                fallbackName = inputName.isEmpty ? "\(S("edu.evaluation.autoIndicatorPrefix")) \(index + 1)" : inputName
            } else {
                fallbackName = "\(S("edu.evaluation.autoIndicatorPrefix")) \(index + 1)"
            }
            filtered.append(
                EvaluationIndicatorDescriptor(
                    id: "connected-\(order)-\(index)",
                    name: fallbackName,
                    kind: .score
                )
            )
        }

        return filtered
    }

    func parseEvaluationIndicators(
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

    func isCompletionIndicatorType(_ raw: String) -> Bool {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        let tokens = ["completion", "complete", "done", "binary", "yes/no", "完成", "达成", "完成制"]
        return tokens.contains(where: { normalized.contains($0) })
    }

    func parseJSONStringDictionary(_ raw: String?) -> [String: String] {
        guard let raw, !raw.isEmpty, let data = raw.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    func parsedStudentRosterEntries(from studentProfile: String) -> [StudentRosterEntry] {
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

        struct PendingEntry {
            let sequence: Int?
            let name: String
            let group: String
        }
        var pending: [PendingEntry] = []

        for line in lines {
            if line.contains("="), !line.contains("|"), !line.contains(",") {
                continue
            }

            let columns: [String]
            if line.contains("|") {
                columns = line
                    .split(separator: "|", omittingEmptySubsequences: false)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            } else if line.contains(",") {
                columns = line
                    .split(separator: ",", omittingEmptySubsequences: false)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            } else {
                columns = [line]
            }

            let sequenceCandidate = columns.first.flatMap { Int($0) }
            let name: String
            let group: String
            switch columns.count {
            case let count where count >= 4:
                if sequenceCandidate != nil {
                    name = columns[1]
                    group = columns[2]
                } else {
                    name = columns[0]
                    group = columns[1]
                }
            case 3:
                if sequenceCandidate != nil {
                    name = columns[1]
                    group = columns[2]
                } else {
                    name = columns[0]
                    group = columns[1]
                }
            case 2:
                if sequenceCandidate != nil {
                    name = columns[1]
                    group = ""
                } else {
                    name = columns[0]
                    group = columns[1]
                }
            default:
                name = columns[0]
                group = ""
            }

            let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowered = normalizedName.lowercased()
            if normalizedName.isEmpty || lowered == "name" || normalizedName == "姓名" {
                continue
            }
            pending.append(
                PendingEntry(
                    sequence: sequenceCandidate,
                    name: normalizedName,
                    group: group.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        }

        var seenNames = Set<String>()
        let uniquePending = pending.filter { entry in
            seenNames.insert(entry.name).inserted
        }

        var usedSequences = Set<Int>()
        var nextSequence = 1
        var roster: [StudentRosterEntry] = []
        for entry in uniquePending {
            let sequence: Int
            if let candidate = entry.sequence,
               candidate > 0,
               usedSequences.insert(candidate).inserted {
                sequence = candidate
            } else {
                while usedSequences.contains(nextSequence) {
                    nextSequence += 1
                }
                sequence = nextSequence
                usedSequences.insert(sequence)
                nextSequence += 1
            }

            roster.append(
                StudentRosterEntry(
                    sequence: sequence,
                    name: entry.name,
                    group: entry.group
                )
            )
        }

        return roster.sorted { lhs, rhs in
            if lhs.sequence != rhs.sequence {
                return lhs.sequence < rhs.sequence
            }
            return lhs.name < rhs.name
        }
    }

    func parsedStudentNames(from studentProfile: String) -> [String] {
        parsedStudentRosterEntries(from: studentProfile).map(\.name)
    }

    func extractedRosterText(from studentProfile: String) -> String? {
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

    func openStudentRosterEditor(for file: GNodeWorkspaceFile) {
        creationDraft = CourseCreationDraft()
        creationDraft.studentRosterText = extractedRosterText(from: file.studentProfile) ?? ""
        studentRosterEditFileID = file.id
        showingStudentRosterEdit = true
    }

    func saveStudentRoster(_ newRoster: String) {
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

    func openCourseEditor(for file: GNodeWorkspaceFile) {
        var draft = CourseCreationDraft()
        draft.courseName = file.name
        draft.gradeInputMode = file.gradeMode == "age" ? .age : .grade
        draft.gradeMinText = "\(file.gradeMin)"
        draft.gradeMaxText = "\(file.gradeMax)"
        draft.subject = file.subject
        draft.lessonDurationMinutesText = "\(file.lessonDurationMinutes)"
        draft.periodRange = file.periodRange
        draft.studentCountText = "\(file.studentCount)"
        draft.priorAssessmentScoreText = file.studentPriorKnowledgeLevel
        draft.assignmentCompletionRateText = file.studentMotivationLevel
        draft.studentSupportNotes = file.studentSupportNotes
        draft.goals = file.goalsText
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        draft.modelID = file.modelID
        draft.leadTeacherCountText = "\(file.leadTeacherCount)"
        draft.assistantTeacherCountText = "\(file.assistantTeacherCount)"
        draft.teacherRolePlan = file.teacherRolePlan
        draft.resourceConstraints = file.resourceConstraints
        draft.studentRosterText = extractedRosterText(from: file.studentProfile) ?? ""
        draft.totalSessionsText = "\(file.totalSessions)"
        if let lt = CourseLessonType(rawValue: file.lessonType) { draft.lessonType = lt }
        if let ts = TeachingStyleMode(rawValue: file.teachingStyle) { draft.teachingStyle = ts }
        if let fc = FormativeCheckIntensity(rawValue: file.formativeCheckIntensity) { draft.formativeCheckIntensity = fc }
        draft.emphasizeInquiryExperiment = file.emphasizeInquiryExperiment
        draft.emphasizeExperienceReflection = file.emphasizeExperienceReflection
        draft.requireStructuredFlow = file.requireStructuredFlow

        // Parse learning organization from studentProfile
        let profile = file.studentProfile
        if let orgRange = profile.range(of: "organization=") {
            let suffix = profile[orgRange.upperBound...]
            let orgStr = String(suffix.prefix(while: { $0 != "," && $0 != " " }))
            if let mode = LearningOrganizationMode(rawValue: orgStr) {
                draft.learningOrganization = mode
            }
        }
        // Parse supportNeed count
        if let snRange = profile.range(of: "supportNeed=") {
            let suffix = profile[snRange.upperBound...]
            let numStr = String(suffix.prefix(while: { $0.isNumber }))
            draft.supportNeedCountText = numStr
        }

        creationDraft = draft
        editingCourseOriginalModelID = file.modelID
        editingCourseFileID = file.id
        showingEditCourseSheet = true
    }

    func saveCourseEdits() {
        guard let fileID = editingCourseFileID,
              let file = workspaceFiles.first(where: { $0.id == fileID }) else {
            showingEditCourseSheet = false
            return
        }

        let modelChanged = creationDraft.modelID != editingCourseOriginalModelID

        file.name = creationDraft.courseName
        file.gradeMode = creationDraft.gradeInputMode.rawValue
        file.gradeMin = creationDraft.normalizedGradeRange.0
        file.gradeMax = creationDraft.normalizedGradeRange.1
        file.gradeLevel = creationDraft.gradeLevelSummary
        file.subject = creationDraft.subject
        file.lessonDurationMinutes = creationDraft.lessonDurationMinutes
        file.periodRange = creationDraft.periodRange
        file.studentCount = creationDraft.studentCount
        file.studentProfile = creationDraft.studentProfileSummary
        file.studentPriorKnowledgeLevel = "\(creationDraft.priorAssessmentScore)"
        file.studentMotivationLevel = "\(creationDraft.assignmentCompletionRate)"
        file.studentSupportNotes = creationDraft.studentSupportNotes
        file.goalsText = creationDraft.goalsText
        file.modelID = creationDraft.modelID
        file.teacherTeam = creationDraft.teacherTeamSummary
        file.leadTeacherCount = creationDraft.leadTeacherCount
        file.assistantTeacherCount = creationDraft.assistantTeacherCount
        file.teacherRolePlan = creationDraft.teacherRolePlan
        file.resourceConstraints = creationDraft.resourceConstraints
        file.totalSessions = creationDraft.totalSessions
        file.lessonType = creationDraft.lessonType.rawValue
        file.teachingStyle = creationDraft.teachingStyle.rawValue
        file.formativeCheckIntensity = creationDraft.formativeCheckIntensity.rawValue
        file.emphasizeInquiryExperiment = creationDraft.emphasizeInquiryExperiment
        file.emphasizeExperienceReflection = creationDraft.emphasizeExperienceReflection
        file.requireStructuredFlow = creationDraft.requireStructuredFlow
        file.updatedAt = .now

        try? modelContext.save()
        showingEditCourseSheet = false

        if modelChanged {
            showingModelChangeWarning = true
        }
    }

    func deduplicatedStudentNames(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            if seen.insert(value).inserted {
                result.append(value)
            }
        }
        return result
    }

}
