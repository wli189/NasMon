//
//  FeatureSelectionView.swift
//  NasMon
//
//  Created by Brian Li on 7/30/26.
//

import SwiftUI

struct FeatureSelectionView: View {
    @Bindable var sessionViewModel: SessionViewModel
    @State private var dashboardViewModel = DashboardViewModel()
    @State private var selectedTab: MainTab = .files

    var body: some View {
        TabView(selection: $selectedTab) {
            FileManagerNavigationRoot(sessionViewModel: sessionViewModel)
            .tabItem {
                Label(MainTab.files.title, systemImage: MainTab.files.systemImage)
            }
            .tag(MainTab.files)

            if sessionViewModel.isAdmin {
                TabRootView {
                    DashboardView(
                        viewModel: dashboardViewModel,
                        sessionViewModel: sessionViewModel
                    )
                }
                .tabItem {
                    Label(MainTab.dashboard.title, systemImage: MainTab.dashboard.systemImage)
                }
                .tag(MainTab.dashboard)
            }
        }
        .tint(Color.nasMonAccent)
        .background(Color.nasMonPageBackground.ignoresSafeArea())
        .onAppear {
            dashboardViewModel.activeClient = sessionViewModel.activeClient
        }
        .onChange(of: sessionViewModel.activeClient) { _, newClient in
            dashboardViewModel.activeClient = newClient
        }
        .onChange(of: sessionViewModel.isAdmin) { _, isAdmin in
            if !isAdmin {
                selectedTab = .files
                dashboardViewModel.stopPolling()
            }
        }
    }

    private enum MainTab: Hashable {
        case files
        case dashboard

        var title: String {
            switch self {
            case .files:
                return "Files"
            case .dashboard:
                return "Dashboard"
            }
        }

        var systemImage: String {
            switch self {
            case .files:
                return "folder"
            case .dashboard:
                return "gauge.with.dots.needle.33percent"
            }
        }
    }
}

private struct TabRootView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            content
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.nasMonSurface, for: .navigationBar)
    }
}

#Preview {
    FeatureSelectionView(sessionViewModel: SessionViewModel())
}
