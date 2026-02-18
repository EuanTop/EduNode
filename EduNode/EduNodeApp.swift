//
//  EduNodeApp.swift
//  EduNode
//
//  Created by Euan on 2/15/26.
//

import SwiftUI
import SwiftData
import TipKit
#if canImport(UIKit)
import UIKit
#endif

@main
@MainActor
struct EduNodeApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            GNodeWorkspaceFile.self,
        ])
        return makeModelContainer(schema: schema)
    }()

    init() {
        try? Tips.configure()
        EduNodePluginConfig.configureIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .onAppear {
                    configureCatalystTitlebarIfNeeded()
                }
        }
        .modelContainer(sharedModelContainer)
    }

    private static func makeModelContainer(schema: Schema) -> ModelContainer {
        let diskConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        if let container = try? ModelContainer(for: schema, configurations: [diskConfig]) {
            return container
        }

        cleanupPotentiallyBrokenStoreFiles()
        if let container = try? ModelContainer(for: schema, configurations: [diskConfig]) {
            return container
        }

        let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        if let container = try? ModelContainer(for: schema, configurations: [memoryConfig]) {
            return container
        }

        preconditionFailure("Unable to initialize SwiftData model container")
    }

    private static func cleanupPotentiallyBrokenStoreFiles() {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let knownNames = [
            "default.store", "default.store-wal", "default.store-shm",
            "default.sqlite", "default.sqlite-wal", "default.sqlite-shm"
        ]
        for name in knownNames {
            let url = appSupport.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }

        if let items = try? fm.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: nil) {
            for url in items {
                let file = url.lastPathComponent.lowercased()
                if file.hasPrefix("default.store") || file.hasPrefix("default.sqlite") {
                    try? fm.removeItem(at: url)
                }
            }
        }
    }

    @MainActor
    private func configureCatalystTitlebarIfNeeded() {
        #if targetEnvironment(macCatalyst)
        for case let windowScene as UIWindowScene in UIApplication.shared.connectedScenes {
            guard let titlebar = windowScene.titlebar else { continue }
            titlebar.titleVisibility = .hidden
            titlebar.toolbar = nil
        }
        #endif
    }
}
