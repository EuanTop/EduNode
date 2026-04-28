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

extension Notification.Name {
    static let eduNodeCommandNewCourse = Notification.Name("edunode.command.newCourse")
    static let eduNodeCommandImportCourse = Notification.Name("edunode.command.importCourse")
    static let eduNodeCommandOpenDocumentation = Notification.Name("edunode.command.openDocumentation")
    static let eduNodeCommandOpenTutorialGuide = Notification.Name("edunode.command.openTutorialGuide")
    static let eduNodeCommandOpenAccount = Notification.Name("edunode.command.openAccount")
}

@main
@MainActor
struct EduNodeApp: App {
    @State private var didConfigureWindowChrome = false

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            GNodeWorkspaceFile.self,
        ])
        return makeModelContainer(schema: schema)
    }()

    init() {
        bootLog("EduNodeApp.init")
        try? Tips.configure()
        EduNodePluginConfig.configureIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .onAppear {
                    bootLog("WindowGroup.onAppear")
                    configureWindowChromeOnceIfNeeded()
                }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandMenu("Course") {
                Button("New Course") {
                    NotificationCenter.default.post(name: .eduNodeCommandNewCourse, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Import Course…") {
                    NotificationCenter.default.post(name: .eduNodeCommandImportCourse, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandMenu("Guides") {
                Button("Documentation") {
                    NotificationCenter.default.post(name: .eduNodeCommandOpenDocumentation, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Tutorial Guide") {
                    NotificationCenter.default.post(name: .eduNodeCommandOpenTutorialGuide, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }

            CommandMenu("Account") {
                Button("Account…") {
                    NotificationCenter.default.post(name: .eduNodeCommandOpenAccount, object: nil)
                }
            }
        }
    }

    private func bootLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let tagged = "EDUNODE_BOOT | \(timestamp) | \(message)"
        print(tagged)
        NSLog("%@", tagged)
        UserDefaults.standard.set(tagged, forKey: "edunode.lastBootLog")
        appendDiagnosticLogLine(tagged)
    }

    private func appendDiagnosticLogLine(_ line: String) {
        let fileManager = FileManager.default
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let url = documents.appendingPathComponent("edunode_debug.log")
        guard let data = (line + "\n").data(using: .utf8) else { return }

        if fileManager.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
                return
            } catch {
                try? handle.close()
            }
        }

        try? data.write(to: url, options: .atomic)
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
    private func configureWindowChromeOnceIfNeeded() {
        guard !didConfigureWindowChrome else { return }
        didConfigureWindowChrome = true

        configureWindowChromeIfNeeded()
        DispatchQueue.main.async {
            configureWindowChromeIfNeeded()
        }
    }

    @MainActor
    private func configureWindowChromeIfNeeded() {
        #if canImport(UIKit)
        let shouldClearWindowTitle = ProcessInfo.processInfo.isiOSAppOnMac

        for case let windowScene as UIWindowScene in UIApplication.shared.connectedScenes {
            if shouldClearWindowTitle {
                windowScene.title = ""
            }

            #if targetEnvironment(macCatalyst)
            if let titlebar = windowScene.titlebar {
                titlebar.titleVisibility = .hidden
                titlebar.toolbar = nil
            }
            windowScene.title = ""
            #endif
        }
        #endif
    }
}
