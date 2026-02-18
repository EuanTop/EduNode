import Foundation
import GNodeKit

final class EduTextNode: GNode, NodeTextEditable {
    let id: UUID
    var attributes: NodeAttributes
    var inputs: [AnyInputPort]
    var outputs: [AnyOutputPort]

    private var userValue: StringData
    private let placeholder: String

    init(name: String, value: String = "", outputName: String, placeholder: String) {
        self.id = UUID()
        self.attributes = NodeAttributes(name: name)
        self.inputs = []
        self.outputs = [AnyOutputPort(name: outputName, dataType: "String")]
        self.userValue = StringData(value)
        self.placeholder = placeholder
    }

    func process() throws {
        guard attributes.isRun else {
            throw GNodeError.nodeDisabled(id: id)
        }
        try outputs[0].setValue(userValue)
    }

    func canExecute() -> Bool {
        attributes.isRun
    }

    var editorTextValue: String {
        get { userValue.value }
        set { userValue = StringData(newValue) }
    }

    var editorTextPlaceholder: String {
        placeholder
    }
}

final class EduKnowledgeNode: GNode, NodeTextEditable, NodeOptionSelectable {
    let id: UUID
    var attributes: NodeAttributes
    var inputs: [AnyInputPort]
    var outputs: [AnyOutputPort]

    private var content: StringData
    private var level: String

    init(name: String, content: String = "", level: String = EduKnowledgeNode.defaultLevel) {
        self.id = UUID()
        self.attributes = NodeAttributes(name: name)
        self.inputs = [
            AnyInputPort(name: S("edu.knowledge.input.type"), dataType: "Any", allowsMultipleConnections: true),
            AnyInputPort(name: S("edu.knowledge.input.content"), dataType: "Any", allowsMultipleConnections: true),
            AnyInputPort(name: S("edu.knowledge.input.previous"), dataType: "Any", allowsMultipleConnections: true)
        ]
        self.outputs = [
            AnyOutputPort(name: S("edu.knowledge.output.content"), dataType: "String"),
            AnyOutputPort(name: S("edu.knowledge.output.level"), dataType: "String")
        ]
        self.content = StringData(content)
        self.level = Self.levelOptions.contains(level) ? level : Self.defaultLevel
    }

    func process() throws {
        guard attributes.isRun else {
            throw GNodeError.nodeDisabled(id: id)
        }

        let incomingLevel = normalizedLevelInput(at: 0)
        let incomingContent = normalizedStringInput(at: 1)
        let previousContent = normalizedStringInput(at: 2)

        let localContent = content.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedContent = !incomingContent.isEmpty
            ? incomingContent
            : (!localContent.isEmpty ? localContent : previousContent)
        let resolvedLevel = !incomingLevel.isEmpty ? incomingLevel : level

        if Self.levelOptions.contains(resolvedLevel) {
            level = resolvedLevel
        }

        try outputs[0].setValue(StringData(resolvedContent))
        try outputs[1].setValue(StringData(resolvedLevel))
    }

    func canExecute() -> Bool {
        attributes.isRun
    }

    var editorTextValue: String {
        get { content.value }
        set { content = StringData(newValue) }
    }

    var editorTextPlaceholder: String {
        S("edu.knowledge.placeholder")
    }

    var editorPrefersMultiline: Bool {
        true
    }

    var editorMinVisibleLines: Int {
        3
    }

    var editorSelectedOption: String {
        get { level }
        set {
            guard Self.levelOptions.contains(newValue) else { return }
            level = newValue
        }
    }

    var editorOptionLabel: String {
        S("edu.knowledge.level.label")
    }

    var editorOptions: [String] {
        Self.levelOptions
    }

    static var levelOptions: [String] {
        [
            S("edu.knowledge.level.basic"),
            S("edu.knowledge.level.intermediate"),
            S("edu.knowledge.level.advanced")
        ]
    }

    static var defaultLevel: String {
        levelOptions[0]
    }

    private func normalizedStringInput(at index: Int) -> String {
        guard inputs.indices.contains(index) else { return "" }
        guard let raw = stringValue(from: inputs[index]) else { return "" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedLevelInput(at index: Int) -> String {
        let raw = normalizedStringInput(at: index)
        guard !raw.isEmpty else { return "" }

        let candidates = raw
            .components(separatedBy: CharacterSet.newlines.union(.init(charactersIn: ",|/")))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return candidates.first(where: { Self.levelOptions.contains($0) }) ?? raw
    }

    private func stringValue(from input: AnyInputPort) -> String? {
        if let value: StringData = ((try? input.getValue()) ?? nil) {
            return value.value
        }
        if let value: NumData = ((try? input.getValue()) ?? nil) {
            let number = value.toDouble()
            return number == number.rounded() ? "\(Int(number))" : "\(number)"
        }
        if let value: BoolData = ((try? input.getValue()) ?? nil) {
            return value.value ? "true" : "false"
        }
        if let value: ArrayData = ((try? input.getValue()) ?? nil) {
            return value.values
                .map { number in
                    number == number.rounded() ? "\(Int(number))" : "\(number)"
                }
                .joined(separator: ", ")
        }
        if let value: ObjectData = ((try? input.getValue()) ?? nil) {
            let fields = value.keys.map { key -> String in
                let display = value.get(key)?.displayString() ?? ""
                return "\(key): \(display)"
            }
            return "{\(fields.joined(separator: ", "))}"
        }
        return nil
    }
}

final class EduToolkitNode: GNode, NodeTextEditable, NodeOptionSelectable {
    let id: UUID
    var attributes: NodeAttributes
    var inputs: [AnyInputPort]
    var outputs: [AnyOutputPort]

    private var activityText: StringData
    private var toolkitType: String

    init(name: String, value: String = "", selectedType: String = EduToolkitNode.defaultType) {
        self.id = UUID()
        self.attributes = NodeAttributes(name: name)
        self.inputs = [
            AnyInputPort(name: S("edu.toolkit.input.knowledge"), dataType: "Any", allowsMultipleConnections: true),
            AnyInputPort(name: S("edu.toolkit.input.support"), dataType: "Any", allowsMultipleConnections: true)
        ]
        self.outputs = [
            AnyOutputPort(name: S("edu.output.toolkit"), dataType: "String"),
            AnyOutputPort(name: S("edu.toolkit.output.type"), dataType: "String")
        ]
        self.activityText = StringData(value)
        self.toolkitType = Self.typeOptions.contains(selectedType) ? selectedType : Self.defaultType
    }

    func process() throws {
        guard attributes.isRun else {
            throw GNodeError.nodeDisabled(id: id)
        }

        let knowledgeInput = normalizedStringInput(at: 0)
        let supportInput = normalizedStringInput(at: 1)
        let localText = activityText.value.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = []
        if !knowledgeInput.isEmpty { parts.append(knowledgeInput) }
        if !localText.isEmpty { parts.append(localText) }
        if !supportInput.isEmpty { parts.append(supportInput) }

        let resolvedText = parts.joined(separator: "\n")
        try outputs[0].setValue(StringData(resolvedText))
        try outputs[1].setValue(StringData(toolkitType))
    }

    func canExecute() -> Bool {
        attributes.isRun
    }

    var editorTextValue: String {
        get { activityText.value }
        set { activityText = StringData(newValue) }
    }

    var editorTextPlaceholder: String {
        S("edu.toolkit.placeholder")
    }

    var editorPrefersMultiline: Bool {
        true
    }

    var editorMinVisibleLines: Int {
        3
    }

    var editorSelectedOption: String {
        get { toolkitType }
        set {
            guard Self.typeOptions.contains(newValue) else { return }
            toolkitType = newValue
        }
    }

    var editorOptionLabel: String {
        S("edu.toolkit.type.label")
    }

    var editorOptions: [String] {
        Self.typeOptions
    }

    static var typeOptions: [String] {
        [
            S("edu.toolkit.type.game"),
            S("edu.toolkit.type.observation"),
            S("edu.toolkit.type.discussion"),
            S("edu.toolkit.type.inquiry"),
            S("edu.toolkit.type.practice"),
            S("edu.toolkit.type.peerReview"),
            S("edu.toolkit.type.demonstration")
        ]
    }

    static var defaultType: String {
        typeOptions[0]
    }

    private func normalizedStringInput(at index: Int) -> String {
        guard inputs.indices.contains(index) else { return "" }
        guard let raw = stringValue(from: inputs[index]) else { return "" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stringValue(from input: AnyInputPort) -> String? {
        if let value: StringData = ((try? input.getValue()) ?? nil) {
            return value.value
        }
        if let value: NumData = ((try? input.getValue()) ?? nil) {
            let number = value.toDouble()
            return number == number.rounded() ? "\(Int(number))" : "\(number)"
        }
        if let value: BoolData = ((try? input.getValue()) ?? nil) {
            return value.value ? "true" : "false"
        }
        if let value: ArrayData = ((try? input.getValue()) ?? nil) {
            return value.values
                .map { number in
                    number == number.rounded() ? "\(Int(number))" : "\(number)"
                }
                .joined(separator: ", ")
        }
        if let value: ObjectData = ((try? input.getValue()) ?? nil) {
            let fields = value.keys.map { key -> String in
                let display = value.get(key)?.displayString() ?? ""
                return "\(key): \(display)"
            }
            return "{\(fields.joined(separator: ", "))}"
        }
        return nil
    }
}

private func S(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
