//
//  NasMonApp.swift
//  NasMon
//
//  Created by Brian Li on 7/30/26.
//

import SwiftUI

@main
struct NasMonApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Root view that properly observes the @Observable view model.
/// `@State` in a `View` correctly tracks `@Observable` property changes,
/// which is more reliable than `@State` directly in the `App` struct.
struct RootView: View {
    @State private var sessionViewModel = SessionViewModel()
    
    var body: some View {
        Group {
            switch sessionViewModel.connectionState {
            case .idle, .loggingIn, .failed:
                ServerSelectionView(viewModel: sessionViewModel)
            case .loggedIn:
                FeatureSelectionView(sessionViewModel: sessionViewModel)
            }
        }
        .task {
            // Try to resume a saved session first (valid SID means auto-login)
            await sessionViewModel.resumeSession()
        }
    }
}