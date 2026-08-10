//
//  ServerSelectionView.swift
//  NasMon
//
//  Created by Brian Li on 7/30/26.
//

import SwiftUI

struct ServerSelectionView: View {
    @Bindable var viewModel: SessionViewModel
    @State private var showAddServer = false
    @State private var selectedServer: SavedServer?
    @State private var editingServer: SavedServer?
    @State private var showSettings = false
    @State private var showAbout = false

    /// Whether to reload the server list from storage on appear.
    /// Disabled in previews so sample data isn't overwritten.
    var loadServersOnAppear: Bool = true

    /// Whether the given server is the currently active session (has a valid sid).
    private func isActive(_ server: SavedServer) -> Bool {
        guard let client = viewModel.activeClient, client.sid != nil else { return false }
        return client.host == server.host && client.port == server.port
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Servers")
                .toolbar {
                    if !viewModel.savedServers.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showAddServer = true
                            } label: {
                                Label("Add Server", systemImage: "plus")
                            }
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                showSettings = true
                            } label: {
                                Label("Settings", systemImage: "gearshape")
                            }

                            Button {
                                showAbout = true
                            } label: {
                                Label("About", systemImage: "info.circle")
                            }
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                        }
                        .accessibilityLabel("More options")
                    }
                }
                .sheet(isPresented: $showSettings) {
                    NavigationStack {
                        SettingsView()
                    }
                }
                .sheet(isPresented: $showAbout) {
                    NavigationStack {
                        AboutView()
                    }
                }
                .sheet(item: $selectedServer) { server in
                    loginSheet(for: server)
                }
                .sheet(item: $editingServer) { server in
                    loginSheet(for: server)
                }
                .sheet(isPresented: $showAddServer) {
                    NavigationStack {
                        LoginView(viewModel: viewModel, prefillHost: "", prefillAccount: "")
                    }
                }
                // Auto-presented on app startup when the saved password is stale
                // (DSM error 407). The user is prompted to re-enter credentials
                // without having to manually tap the server.
                .sheet(item: $viewModel.pendingLoginServer) { server in
                    loginSheet(for: server)
                }
                .onAppear {
                    if loadServersOnAppear {
                        viewModel.loadServers()
                    }
                }
                .onChange(of: viewModel.connectionState) { _, newState in
                    if newState == .idle {
                        viewModel.loadServers()
                    }
                }
                // Show an alert when auto-login fails on the server selection page
                // (e.g. timeout, unreachable host). LoginView owns credential errors.
                .alert(
                    "Connection Failed",
                    isPresented: Binding(
                        get: {
                            if case .failed = viewModel.connectionState,
                               selectedServer == nil,
                               editingServer == nil,
                               !showAddServer,
                               viewModel.pendingLoginServer == nil {
                                return true
                            }
                            return false
                        },
                        set: { isPresented in
                            if !isPresented {
                                viewModel.connectionState = .idle
                            }
                        }
                    )
                ) {
                    Button("OK", role: .cancel) {
                        viewModel.connectionState = .idle
                    }
                } message: {
                    if case .failed(let message) = viewModel.connectionState {
                        Text(message)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.savedServers.isEmpty {
            NasMonContentStateView(
                kind: .empty,
                title: "No Saved Servers",
                message: "Add your first NAS server to get started.",
                actionTitle: "Add New Server",
                action: { showAddServer = true }
            )
            .padding(.horizontal, NasMonSpacing.pageHorizontal)
            .background(Color.nasMonPageBackground)
        } else {
            List {
                Section {
                    ForEach(viewModel.savedServers) { server in
                        SavedServerRow(
                            server: server,
                            isActive: isActive(server),
                            isLoading: viewModel.autoLoggingInServerID == server.id,
                            onSelect: { select(server) }
                        )
                        .listRowInsets(
                            EdgeInsets(
                                top: NasMonSpacing.small,
                                leading: NasMonSpacing.pageHorizontal,
                                bottom: NasMonSpacing.small,
                                trailing: NasMonSpacing.pageHorizontal
                            )
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task {
                                    await viewModel.removeServer(server)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                editingServer = server
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(Color.nasMonAccent)
                        }
                    }
                } header: {
                    Text("Saved Servers")
                        .font(NasMonTypography.metadata.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                        .padding(.top, NasMonSpacing.small)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.nasMonPageBackground)
        }
    }

    private func select(_ server: SavedServer) {
        guard viewModel.autoLoggingInServerID == nil else { return }

        Task {
            let didAutoLogin = await viewModel.autoLogin(to: server)
            if !didAutoLogin {
                selectedServer = server
            }
        }
    }

    @ViewBuilder
    private func loginSheet(for server: SavedServer) -> some View {
        NavigationStack {
            LoginView(
                viewModel: viewModel,
                prefillHost: "\(server.host):\(server.port)",
                prefillAccount: server.lastLoginAccount ?? "",
                prefillName: server.name
            )
        }
    }
}

private struct SavedServerRow: View {
    let server: SavedServer
    let isActive: Bool
    let isLoading: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            NasMonCard {
                HStack(alignment: .top, spacing: NasMonSpacing.medium) {
                    Image(systemName: "server.rack")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.nasMonAccent)
                        .frame(width: 36, height: 36)
                        .background(Color.nasMonAccent.opacity(0.12), in: Circle())
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: NasMonSpacing.small) {
                        HStack(alignment: .firstTextBaseline, spacing: NasMonSpacing.small) {
                            Text(server.displayName)
                                .font(NasMonTypography.cardTitle)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Spacer(minLength: NasMonSpacing.small)

                            if isActive {
                                NasMonStatusBadge(
                                    "Active",
                                    systemImage: "checkmark.circle.fill",
                                    tint: Color.nasMonOnline
                                )
                            }
                        }

                        VStack(alignment: .leading, spacing: NasMonSpacing.xSmall) {
                            Label("\(server.host):\(server.port)", systemImage: "network")

                            if let account = server.lastLoginAccount {
                                Label(account, systemImage: "person")
                            }
                        }
                        .font(NasMonTypography.supporting)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.nasMonAccent)
                            .accessibilityLabel("Connecting")
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityHint(Text(isLoading ? "Connecting" : "Double-tap to connect"))
    }
}

#Preview {
    let viewModel = SessionViewModel()
    // Populate sample servers for preview purposes
    viewModel.savedServers = [
        SavedServer(host: "192.168.1.100", port: 5001, name: "Home NAS", lastLoginAccount: "admin"),
        SavedServer(host: "100.64.0.5", port: 5001, name: "Tailscale NAS", lastLoginAccount: "brian"),
        SavedServer(host: "in155n.synology.me", port: 5001, name: "Office NAS", lastLoginAccount: "ops")
    ]
    // Simulate an active session on the first server so the "Active" badge shows.
    let client = DSMClient(host: "192.168.1.100", port: 5001)
    client.sid = "preview_sid"
    viewModel.activeClient = client
    return ServerSelectionView(viewModel: viewModel, loadServersOnAppear: false)
}
