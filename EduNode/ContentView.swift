//
//  ContentView.swift
//  EduNode
//
//  Created by Euan on 2/15/26.
//

import SwiftUI
import gnode

struct ContentView: View {
    private enum Tab: Hashable {
        case editor
        case docs
    }

    @State private var selectedTab: Tab = .editor

    var body: some View {
        ZStack {
            // 画布始终在底层（全屏）
            NodeEditorView()
                .ignoresSafeArea()

            // 文档视图（覆盖在画布上方）
            if selectedTab == .docs {
                NodeDocumentationView()
                    .transition(.opacity)
            }

            // 顶部页面切换（始终覆盖在最上层）
            VStack {
                Picker("", selection: $selectedTab) {
                    Text("app.tab.editor").tag(Tab.editor)
                    Text("app.tab.docs").tag(Tab.docs)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .padding(.top, 8)

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
    }
}

#Preview {
    ContentView()
}
