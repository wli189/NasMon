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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedSection: MainSection? = .files

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularWidthLayout
            } else {
                compactWidthLayout
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
                selectedSection = .files
                dashboardViewModel.stopPolling()
            }
        }
    }

    private var compactWidthLayout: some View {
        TabView(selection: Binding(
            get: { selectedSection ?? .files },
            set: { selectedSection = $0 }
        )) {
            sectionView(.files)
                .tabItem {
                    Label(MainSection.files.title, systemImage: MainSection.files.systemImage)
                }
                .tag(MainSection.files)

            if sessionViewModel.isAdmin {
                sectionView(.dashboard)
                    .tabItem {
                        Label(MainSection.dashboard.title, systemImage: MainSection.dashboard.systemImage)
                    }
                    .tag(MainSection.dashboard)
            }
        }
    }

    private var regularWidthLayout: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Section("Workspace") {
                    Label(MainSection.files.title, systemImage: MainSection.files.systemImage)
                        .tag(MainSection.files)

                    if sessionViewModel.isAdmin {
                        Label(MainSection.dashboard.title, systemImage: MainSection.dashboard.systemImage)
                            .tag(MainSection.dashboard)
                    }
                }
            }
            .navigationTitle("NasMon")
            .listStyle(.sidebar)
        } detail: {
            sectionView(selectedSection ?? .files)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func sectionView(_ section: MainSection) -> some View {
        switch section {
        case .files:
            FileManagerNavigationRoot(sessionViewModel: sessionViewModel)
        case .dashboard:
            NavigationStackRootView {
                DashboardView(
                    viewModel: dashboardViewModel,
                    sessionViewModel: sessionViewModel
                )
            }
        }
    }

    private enum MainSection: Hashable {
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

private struct NavigationStackRootView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            content
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.nasMonPageBackground, for: .navigationBar)
}
}

#Preview {
    FeatureSelectionView(sessionViewModel: SessionViewModel())
}
