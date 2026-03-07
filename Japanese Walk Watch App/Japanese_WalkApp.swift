//
//  Japanese_WalkApp.swift
//  Japanese Walk Watch App
//
//  Created by Alan K on 2/20/26.
//

import SwiftUI

@main
struct Japanese_Walk_Watch_AppApp: App {
    @StateObject private var sessionManager = WalkingSessionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
        }
        .backgroundTask(.appRefresh("interval.phase-transition")) {
            await sessionManager.handleBackgroundRefresh()
        }
    }
}
