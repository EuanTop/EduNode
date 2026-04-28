import SwiftUI
import GNodeKit

@available(iOS 17.0, macOS 14.0, *)
struct EduDocumentationView: View {
    private struct SidebarMethodItem: Identifiable {
        let id: String
        let title: String
    }

    @State private var selectedType: String?
    @State private var expandedDetailSectionKeys: Set<String> = []
    @State private var expandedSidebarDocTypes: Set<String> = []
    @State private var isSidebarVisible = true

    let initialSelectedNodeType: String?
    let onSelectionChange: ((String?) -> Void)?
    let onClose: (() -> Void)?

    init(
        selectedNodeType: String? = nil,
        onSelectionChange: ((String?) -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.initialSelectedNodeType = selectedNodeType
        self.onSelectionChange = onSelectionChange
        self.onClose = onClose
        let initialType = {
            guard let selectedNodeType,
                  NodeDocumentation.doc(for: selectedNodeType) != nil else {
                return NodeDocumentation.allDocs.first?.type
            }
            return selectedNodeType
        }()
        _selectedType = State(initialValue: initialType)
    }

    private var isChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    private var sidebarBackgroundColor: Color {
        Color(white: 0.12)
    }

    private var detailPanelBackgroundColor: Color {
        Color(white: 0.10)
    }

    private var sortedCategories: [String] {
        NodeDocumentation.categories
    }

    private var windowControlReservedWidth: CGFloat {
        #if targetEnvironment(macCatalyst)
        return 78
        #else
        return 0
        #endif
    }

    private var sidebarHeaderLeadingPadding: CGFloat {
        16 + windowControlReservedWidth
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    if isSidebarVisible {
                        sidebarPanel(width: sidebarWidth(for: geometry.size.width))
                            .zIndex(30)

                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 1)
                            .zIndex(29)
                    }

                    examplePanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .zIndex(0)

                    if let doc = selectedDoc {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 1)
                            .zIndex(39)

                        detailPanel(doc)
                            .frame(width: detailPanelWidth(for: geometry.size.width))
                            .zIndex(40)
                    }
                }
                .background(Color(white: 0.08).ignoresSafeArea())

                if !isSidebarVisible {
                    collapsedHeaderBar(topInset: geometry.safeAreaInsets.top)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            syncSidebarExpansionForSelection()
            syncExpandedDetailSections()
            onSelectionChange?(selectedType)
        }
        .onChange(of: selectedType) { _, newValue in
            syncSidebarExpansionForSelection()
            syncExpandedDetailSections()
            onSelectionChange?(newValue)
        }
    }

    private var selectedDoc: NodeDoc? {
        guard let selectedType else { return nil }
        return NodeDocumentation.doc(for: docBaseType(selectedType))
    }

    private func sidebarWidth(for totalWidth: CGFloat) -> CGFloat {
        min(338, max(292, totalWidth * 0.255))
    }

    private func detailPanelWidth(for totalWidth: CGFloat) -> CGFloat {
        min(340, max(280, totalWidth * 0.22))
    }

    private func sidebarPanel(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            sidebarHeaderBar

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    sidebarIntroCard

                    ForEach(sortedCategories, id: \.self) { categoryKey in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NodeDocumentation.categoryTitle(for: categoryKey))
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)

                            VStack(spacing: 4) {
                                ForEach(NodeDocumentation.docs(in: categoryKey)) { doc in
                                    sidebarDocEntry(for: doc)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 14)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(sidebarBackgroundColor)
    }

    private var sidebarHeaderBar: some View {
        HStack(spacing: 10) {
            docsHeaderButton(
                systemImage: "chevron.left",
                accessibilityLabel: isChinese ? "返回" : "Back"
            ) {
                onClose?()
            }

            docsHeaderButton(
                systemImage: "sidebar.left",
                accessibilityLabel: isChinese ? "隐藏侧栏" : "Hide Sidebar"
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSidebarVisible = false
                }
            }

            Spacer(minLength: 0)

            Text(isChinese ? "Documentation" : "Documentation")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)
        }
        .padding(.leading, sidebarHeaderLeadingPadding)
        .padding(.trailing, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(sidebarBackgroundColor)
    }

    private func collapsedHeaderBar(topInset: CGFloat) -> some View {
        HStack(spacing: 10) {
            docsHeaderButton(
                systemImage: "chevron.left",
                accessibilityLabel: isChinese ? "返回" : "Back"
            ) {
                onClose?()
            }

            docsHeaderButton(
                systemImage: "sidebar.left",
                accessibilityLabel: isChinese ? "显示侧栏" : "Show Sidebar"
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSidebarVisible = true
                }
            }
        }
        .padding(.leading, sidebarHeaderLeadingPadding)
        .padding(.top, topInset + 12)
    }

    private func docsHeaderButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.08), in: Circle())
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var sidebarIntroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isChinese ? "选择节点" : "Select Node")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text(
                isChinese
                    ? "从左侧列表选择节点类型，查看示例结构、详细说明与适用场景。"
                    : "Choose a node type from the list to inspect its example structure, detailed guide, and usage context."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
    }

    private var examplePanel: some View {
        ZStack {
            Color(white: 0.09)

            if let selectedType {
                NodeEditorView(exampleForNodeType: selectedType)
                    .id(selectedType)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Text(isChinese ? "请先从左侧选择一个节点" : "Select a node from the sidebar first.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .clipped()
    }

    private func detailPanel(_ doc: NodeDoc) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(nodeColor(docBaseType(doc.type)))
                        .frame(width: 10, height: 10)

                    Text(doc.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    Text(doc.category)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.10), in: Capsule())
                }

                if let selectedMethodSection = selectedDetailSection(for: doc) {
                    methodGuideSection(doc: doc, section: selectedMethodSection)
                } else {
                    defaultDocSection(doc)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .background(detailPanelBackgroundColor)
    }

    private func methodGuideSection(doc: NodeDoc, section: NodeDocDetailSection) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(section.title)
                .font(.headline)
                .foregroundStyle(.white)

            if let guide = section.methodGuide {
                Text(guide.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Divider().overlay(Color.white.opacity(0.08))

                if !guide.inputs.isEmpty {
                    docPortSection(title: isChinese ? "输入" : "Inputs", icon: "arrow.right.circle", ports: guide.inputs)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label(isChinese ? "处理过程" : "Processing", systemImage: "gearshape")
                        .font(.callout.bold())
                    Text(guide.processDesc)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if !guide.outputs.isEmpty {
                    docPortSection(title: isChinese ? "输出" : "Outputs", icon: "arrow.left.circle", ports: guide.outputs)
                }

                if let scenario = guide.scenario,
                   !scenario.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Divider().overlay(Color.white.opacity(0.08))

                    VStack(alignment: .leading, spacing: 8) {
                        Label(isChinese ? "适用场景" : "Scenario", systemImage: "lightbulb.max")
                            .font(.callout.bold())
                        Text(scenario)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !section.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(section.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func defaultDocSection(_ doc: NodeDoc) -> some View {
        let visibleSections = doc.categoryKey == "model"
            ? doc.detailSections.filter { section in
                section.id != "ipo_overview" && section.id != "node_sequence"
            }
            : doc.detailSections

        return VStack(alignment: .leading, spacing: 18) {
            Text(doc.description)
                .font(.callout)
                .foregroundStyle(.secondary)

            if doc.categoryKey == "model" {
                if !doc.processDesc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(doc.processDesc)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Divider().overlay(Color.white.opacity(0.08))

                if !doc.inputs.isEmpty {
                    docPortSection(title: isChinese ? "输入" : "Inputs", icon: "arrow.right.circle", ports: doc.inputs)
                }

                if !doc.processDesc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(isChinese ? "处理过程" : "Processing", systemImage: "gearshape")
                            .font(.callout.bold())
                        Text(doc.processDesc)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                if !doc.outputs.isEmpty {
                    docPortSection(title: isChinese ? "输出" : "Outputs", icon: "arrow.left.circle", ports: doc.outputs)
                }
            }

            if !visibleSections.isEmpty {
                Divider().overlay(Color.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 10) {
                    Label(isChinese ? "详细说明" : "Detailed Guide", systemImage: "list.bullet.rectangle")
                        .font(.callout.bold())

                    ForEach(visibleSections) { section in
                        DisclosureGroup(
                            isExpanded: bindingForDetailSection(docType: doc.type, sectionID: section.id),
                            content: {
                                Text(section.body)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 4)
                            },
                            label: {
                                Text(section.title)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                        )
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func docPortSection(title: String, icon: String, ports: [PortDoc]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.callout.bold())

            ForEach(Array(ports.enumerated()), id: \.offset) { _, port in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(portColor(port.type))
                        .frame(width: 7, height: 7)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(port.name)
                                .font(.callout.weight(.semibold))
                            Text("(\(port.type))")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if port.isOptional {
                                Text(isChinese ? "可选" : "Optional")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.88))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.10), in: Capsule())
                            }
                        }

                        Text(port.desc)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sidebarDocEntry(for doc: NodeDoc) -> some View {
        if shouldShowMethodSubmenu(for: doc) {
            sidebarNodeRow(
                title: doc.name,
                dotColor: nodeColor(doc.type),
                isSelected: selectedDocBaseType == doc.type
            ) {
                selectedType = doc.type
                toggleSidebarDocExpansion(doc.type)
            }

            if expandedSidebarDocTypes.contains(doc.type) {
                ForEach(sidebarMethodItems(for: doc)) { item in
                    sidebarMethodRow(
                        title: item.title,
                        isSelected: selectedType == item.id
                    ) {
                        selectedType = item.id
                    }
                }
            }
        } else {
            sidebarNodeRow(
                title: doc.name,
                dotColor: nodeColor(doc.type),
                isSelected: selectedDocBaseType == doc.type
            ) {
                selectedType = doc.type
            }
        }
    }

    private func sidebarNodeRow(
        title: String,
        dotColor: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private func sidebarMethodRow(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 42)
            .padding(.trailing, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private func sidebarMethodItems(for doc: NodeDoc) -> [SidebarMethodItem] {
        doc.detailSections.map { section in
            SidebarMethodItem(
                id: detailSectionKey(docType: doc.type, sectionID: section.id),
                title: section.title
            )
        }
    }

    private func toggleSidebarDocExpansion(_ docType: String) {
        if expandedSidebarDocTypes.contains(docType) {
            expandedSidebarDocTypes.remove(docType)
        } else {
            expandedSidebarDocTypes.insert(docType)
        }
    }

    private func shouldShowMethodSubmenu(for doc: NodeDoc) -> Bool {
        doc.categoryKey == "toolkit" && !doc.detailSections.isEmpty
    }

    private func selectedDetailSection(for doc: NodeDoc) -> NodeDocDetailSection? {
        guard let selectedType else { return nil }
        guard let sectionID = docDetailSectionID(selectedType) else { return nil }
        return doc.detailSections.first(where: { $0.id == sectionID })
    }

    private var selectedDocBaseType: String? {
        guard let selectedType else { return nil }
        return docBaseType(selectedType)
    }

    private func docBaseType(_ rawType: String) -> String {
        guard let marker = rawType.range(of: "::") else { return rawType }
        return String(rawType[..<marker.lowerBound])
    }

    private func docDetailSectionID(_ rawType: String) -> String? {
        guard let marker = rawType.range(of: "::") else { return nil }
        let section = String(rawType[marker.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return section.isEmpty ? nil : section
    }

    private func detailSectionKey(docType: String, sectionID: String) -> String {
        "\(docType)::\(sectionID)"
    }

    private func bindingForDetailSection(docType: String, sectionID: String) -> Binding<Bool> {
        let key = detailSectionKey(docType: docType, sectionID: sectionID)
        return Binding(
            get: { expandedDetailSectionKeys.contains(key) },
            set: { isExpanded in
                if isExpanded {
                    expandedDetailSectionKeys.insert(key)
                } else {
                    expandedDetailSectionKeys.remove(key)
                }
            }
        )
    }

    private func syncExpandedDetailSections() {
        guard let selectedType else {
            expandedDetailSectionKeys = []
            return
        }

        let baseType = docBaseType(selectedType)
        guard let doc = NodeDocumentation.doc(for: baseType) else {
            expandedDetailSectionKeys = []
            return
        }

        let initialKeys = doc.detailSections
            .filter(\.initiallyExpanded)
            .map { detailSectionKey(docType: baseType, sectionID: $0.id) }
        var keys = Set(initialKeys)

        if let selectedSection = docDetailSectionID(selectedType),
           doc.detailSections.contains(where: { $0.id == selectedSection }) {
            keys.insert(detailSectionKey(docType: baseType, sectionID: selectedSection))
        }

        expandedDetailSectionKeys = keys
    }

    private func syncSidebarExpansionForSelection() {
        guard let selectedType else { return }
        let baseType = docBaseType(selectedType)
        guard let doc = NodeDocumentation.doc(for: baseType),
              shouldShowMethodSubmenu(for: doc) else { return }
        expandedSidebarDocTypes.insert(baseType)
    }

    private func nodeColor(_ type: String) -> Color {
        let resolvedType = docBaseType(type)
        if let style = NodeVisualStyleRegistry.style(for: resolvedType) {
            return style.menuDotColor
        }

        switch resolvedType.lowercased() {
        case "knowledge":
            return .white.opacity(0.72)
        case "evaluation":
            return .orange
        case "inquiry":
            return .cyan
        case "prototype":
            return .orange
        case "negotiation":
            return .indigo
        case "metacognition":
            return .mint
        default:
            return .gray
        }
    }

    private func portColor(_ type: String) -> Color {
        switch type {
        case "Num": return .blue
        case "Bool": return .green
        case "String": return .orange
        case "Array": return .purple
        case "Object": return .cyan
        default: return .gray
        }
    }
}
