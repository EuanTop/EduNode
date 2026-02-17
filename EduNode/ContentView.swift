//
//  ContentView.swift
//  EduNode
//
//  Created by Euan on 2/15/26.
//

import SwiftUI
import SwiftData
import gnode

struct ContentView: View {
    private enum Tab: Hashable {
        case editor
        case docs
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GNodeWorkspaceFile.createdAt, order: .forward) private var workspaceFiles: [GNodeWorkspaceFile]

    @State private var selectedTab: Tab = .editor
    @State private var selectedFileID: UUID?
    @State private var splitVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        GeometryReader { rootGeometry in
            ZStack {
                Group {
                    if selectedTab == .editor {
                        editorWorkspaceView(toolbarTopPadding: rootGeometry.safeAreaInsets.top + 8)
                    } else {
                        NodeDocumentationView()
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack {
                    topBar
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
        .onAppear {
            ensureWorkspaceSeed()
            syncSelectedWorkspaceFile()
        }
        .onChange(of: workspaceFiles.map(\.id)) { _, _ in
            ensureWorkspaceSeed()
            syncSelectedWorkspaceFile()
        }
    }

    private func editorWorkspaceView(toolbarTopPadding: CGFloat) -> some View {
        NavigationSplitView(columnVisibility: $splitVisibility) {
            List(selection: $selectedFileID) {
                ForEach(workspaceFiles, id: \.id) { file in
                    HStack(spacing: 10) {
                        Image(systemName: selectedFileID == file.id ? "doc.text.fill" : "doc.text")
                            .foregroundStyle(selectedFileID == file.id ? .cyan : .secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .lineLimit(1)
                            Text(file.updatedAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(file.id as UUID?)
                }
            }
            .navigationTitle(S("app.files.title"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        createWorkspaceFile(selectAfterCreate: true)
                    } label: {
                        Label(S("app.files.new"), systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button(role: .destructive) {
                        deleteSelectedWorkspaceFile()
                    } label: {
                        Label(S("app.files.delete"), systemImage: "trash")
                    }
                    .disabled(selectedWorkspaceFile == nil)
                }
            }
        } detail: {
            ZStack {
                if let file = selectedWorkspaceFile {
                    NodeEditorView(
                        documentID: file.id,
                        documentData: file.data,
                        toolbarLeadingPadding: 28,
                        toolbarTrailingPadding: 20,
                        toolbarTopPadding: toolbarTopPadding,
                        onDocumentDataChange: { data in
                            persistWorkspaceFileData(id: file.id, data: data)
                        }
                    )
                    .id(file.id)
                    .ignoresSafeArea()
                } else {
                    Color(white: 0.1)
                        .ignoresSafeArea()
                    Text(S("app.files.empty"))
                        .foregroundStyle(.secondary)
                }
            }
            .background(Color(white: 0.1))
        }
        .navigationSplitViewStyle(.balanced)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    private var tabSwitcher: some View {
        Picker("", selection: $selectedTab) {
            Text(S("app.tab.editor")).tag(Tab.editor)
            Text(S("app.tab.docs")).tag(Tab.docs)
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    private var topBar: some View {
        tabSwitcher
            .padding(.top, 8)
    }

    private var selectedWorkspaceFile: GNodeWorkspaceFile? {
        if let selectedFileID {
            return workspaceFiles.first(where: { $0.id == selectedFileID })
        }
        return workspaceFiles.first
    }

    private func S(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    private func ensureWorkspaceSeed() {
        guard workspaceFiles.isEmpty else { return }
        createWorkspaceFile(selectAfterCreate: true)
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

    private func createWorkspaceFile(selectAfterCreate: Bool) {
        let nextIndex = workspaceFiles.count + 1
        let defaultName = String(format: S("app.files.defaultName"), nextIndex)
        let file = GNodeWorkspaceFile(
            name: defaultName,
            data: emptyDocumentData()
        )
        modelContext.insert(file)
        try? modelContext.save()
        if selectAfterCreate {
            selectedFileID = file.id
        }
    }

    private func deleteSelectedWorkspaceFile() {
        guard let current = selectedWorkspaceFile else { return }
        let currentID = current.id
        let orderedIDs = workspaceFiles.map(\.id)
        let currentIndex = orderedIDs.firstIndex(of: currentID) ?? 0
        let remainingIDs = orderedIDs.filter { $0 != currentID }

        modelContext.delete(current)
        try? modelContext.save()

        if remainingIDs.isEmpty {
            createWorkspaceFile(selectAfterCreate: true)
        } else {
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

    private func emptyDocumentData() -> Data {
        let document = GNodeDocument(nodes: [], connections: [], canvasState: [])
        return (try? encodeDocument(document)) ?? Data()
    }
}

#Preview {
    ContentView()
}
