//
//  GNodeTestView.swift
//  EduNode
//
//  gnode 功能测试视图
//

import SwiftUI
import gnode

struct GNodeTestView: View {
    @State private var testResult: String = NSLocalizedString("app.test.initial", comment: "")
    @State private var isLoading: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            Text(S("app.test.title"))
                .font(.largeTitle)
                .padding()

            ScrollView {
                Text(testResult)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            .frame(maxHeight: 400)

            if isLoading {
                ProgressView()
            }

            VStack(spacing: 12) {
                Button(S("app.test.button.basic")) {
                    testBasicNodes()
                }
                .buttonStyle(.borderedProminent)

                Button(S("app.test.button.graph")) {
                    testGraphExecution()
                }
                .buttonStyle(.borderedProminent)

                Button(S("app.test.button.file")) {
                    testFileOperations()
                }
                .buttonStyle(.borderedProminent)

                Button(S("app.test.button.registry")) {
                    testRegistry()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .padding()
    }

    private func S(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    private func SF(_ key: String, _ args: CVarArg...) -> String {
        String(format: S(key), arguments: args)
    }

    private func boolText(_ value: Bool) -> String {
        value ? S("app.bool.true") : S("app.bool.false")
    }

    func testBasicNodes() {
        testResult = S("app.test.start.basic")

        let numNode = NumNode(name: S("app.test.sample.temperature.name"), value: NumData(23.5))
        numNode.attributes.description = S("app.test.sample.temperature.desc")
        testResult += SF("app.test.line.nodeCreated", "NumNode", numNode.attributes.name)
        testResult += SF("app.test.line.value", "\(numNode.getValue().toDouble())")
        testResult += SF("app.test.line.description", numNode.attributes.description)

        let boolNode = BoolNode(name: S("app.test.sample.enabled.name"), value: true)
        boolNode.attributes.description = S("app.test.sample.enabled.desc")
        testResult += SF("app.test.line.nodeCreated", "BoolNode", boolNode.attributes.name)
        testResult += SF("app.test.line.value", boolText(boolNode.getValue()))
        testResult += SF("app.test.line.description", boolNode.attributes.description)

        let stringNode = StringNode(name: S("app.test.sample.message.name"), value: "Hello, gnode!")
        stringNode.attributes.description = S("app.test.sample.message.desc")
        testResult += SF("app.test.line.nodeCreated", "StringNode", stringNode.attributes.name)
        testResult += SF("app.test.line.value", stringNode.getValue())
        testResult += SF("app.test.line.description", stringNode.attributes.description)

        testResult += S("app.test.done.basic")
    }

    func testGraphExecution() {
        testResult = S("app.test.start.graph")

        do {
            let num1 = NumNode(name: S("app.test.sample.input1"), value: NumData(42))
            let num2 = NumNode(name: S("app.test.sample.input2"), value: NumData(10))
            let bool1 = BoolNode(name: S("app.test.sample.switch"), value: true)

            testResult += S("app.test.graph.createdNodes")

            let graph = NodeGraph()
            graph.addNode(num1)
            graph.addNode(num2)
            graph.addNode(bool1)

            testResult += S("app.test.graph.addedToGraph")

            try graph.execute()

            testResult += S("app.test.graph.success")

            testResult += S("app.test.graph.results")
            testResult += SF("app.test.line.nodeValue", num1.attributes.name, "\(num1.getValue().toDouble())")
            testResult += SF("app.test.line.nodeValue", num2.attributes.name, "\(num2.getValue().toDouble())")
            testResult += SF("app.test.line.nodeValue", bool1.attributes.name, boolText(bool1.getValue()))
            testResult += "\n"

            testResult += S("app.test.done.graph")
        } catch {
            testResult += SF("app.test.error", error.localizedDescription)
        }
    }

    func testFileOperations() {
        testResult = S("app.test.start.file")

        do {
            let num1 = NumNode(name: S("app.test.sample.number1"), value: NumData(100))
            let num2 = NumNode(name: S("app.test.sample.number2"), value: NumData(200))
            let str1 = StringNode(name: S("app.test.sample.text"), value: S("app.test.sample.textValue"))

            testResult += S("app.test.file.createdNodes")

            let tempDir = FileManager.default.temporaryDirectory
            let filePath = tempDir.appendingPathComponent("test.gnode").path

            testResult += SF("app.test.file.path", filePath)

            let success = try output_gnode(
                gnode_addr: filePath,
                allSelectionNode: [num1, num2, str1],
                selectionIncludedUnseen: false
            )

            if success {
                testResult += S("app.test.file.exported")
            }

            let loadedGraph = try import_gnode(gnode_addr: filePath)
            testResult += S("app.test.file.imported")

            let nodes = loadedGraph.getAllNodes()
            testResult += SF("app.test.file.nodeCount", nodes.count)
            for node in nodes {
                testResult += SF("app.test.line.listItem", node.attributes.name)
            }

            testResult += S("app.test.done.file")
        } catch {
            testResult += SF("app.test.error", error.localizedDescription)
        }
    }

    func testRegistry() {
        testResult = S("app.test.start.registry")

        let toolkit = GNodeNodeKit.gnodeNodeKit

        testResult += S("app.test.registry.loaded")

        let types = toolkit.availableNodeTypes()
        testResult += SF("app.test.registry.types", types.count)
        for type in types.sorted() {
            testResult += SF("app.test.line.listItem", type)
        }

        testResult += S("app.test.done.registry")
    }
}

#Preview {
    GNodeTestView()
}
