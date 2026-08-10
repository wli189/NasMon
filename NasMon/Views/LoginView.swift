//
//  LoginView.swift
//  NasMon
//
//  Created by Brian Li on 7/30/26.
//

import SwiftUI

struct LoginView: View {
    @Bindable var viewModel: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var host = ""
    @State private var account = ""
    @State private var password = ""
    @State private var serverName = ""
    @FocusState private var focusedField: Field?

    /// Optional pre-filled host value, e.g. "192.168.1.1:5001"
    let prefillHost: String?
    /// Optional pre-filled account value
    let prefillAccount: String?
    /// Optional pre-filled server name value
    let prefillName: String?

    private enum Field: Hashable {
        case serverName
        case host
        case account
        case password
    }

    private var isAddingServer: Bool {
        prefillHost?.isEmpty ?? true
    }

    private var pageTitle: String {
        isAddingServer ? "Add Server" : "Sign In"
    }

    private var pageDescription: String {
        isAddingServer
            ? "Save a NAS connection for quick access next time."
            : "Enter your credentials to connect to this NAS."
    }

    private var canSubmit: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && viewModel.connectionState != .loggingIn
    }

    init(
        viewModel: SessionViewModel,
        prefillHost: String? = nil,
        prefillAccount: String? = nil,
        prefillName: String? = nil
    ) {
        self.viewModel = viewModel
        self.prefillHost = prefillHost
        self.prefillAccount = prefillAccount
        self.prefillName = prefillName
    }

    var body: some View {
        Form {
            introSection
            serverSection
            credentialsSection
            securitySection
            connectionErrorSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.nasMonPageBackground)
        .navigationTitle(pageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: cancel)
                    .disabled(viewModel.connectionState == .loggingIn)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(action: submit) {
                    if viewModel.connectionState == .loggingIn {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                            .accessibilityLabel("Connecting")
                    } else {
                        Text(isAddingServer ? "Add" : "Connect")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
                .accessibilityLabel(isAddingServer ? "Add server" : "Connect to server")
            }
        }
        .onAppear(perform: applyPrefillValues)
        .onChange(of: viewModel.connectionState) { _, newState in
            if case .loggedIn = newState {
                dismiss()
            }
        }
        .onDisappear {
            // A failed login belongs to this sheet. Do not let it become a
            // server-list alert after the user closes the form.
            if case .failed = viewModel.connectionState {
                viewModel.connectionState = .idle
            }
        }
    }

    private var introSection: some View {
        Section {
            VStack(spacing: NasMonSpacing.medium) {
                Image(systemName: "server.rack")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.nasMonAccent)
                    .frame(width: 64, height: 64)
                    .background(Color.nasMonAccent.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)

                VStack(spacing: NasMonSpacing.xSmall) {
                    Text(pageTitle)
                        .font(NasMonTypography.pageTitle)
                        .foregroundStyle(.primary)

                    Text(pageDescription)
                        .font(NasMonTypography.supporting)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, NasMonSpacing.medium)
            .listRowBackground(Color.clear)
            .listRowInsets(
                EdgeInsets(
                    top: NasMonSpacing.small,
                    leading: NasMonSpacing.pageHorizontal,
                    bottom: NasMonSpacing.medium,
                    trailing: NasMonSpacing.pageHorizontal
                )
            )
        }
    }

    private var serverSection: some View {
        Section {
            LoginFieldRow(systemImage: "tag", title: "Name") {
                TextField("Optional", text: $serverName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .serverName)
                    .onSubmit { focusedField = .host }
            }
        } header: {
            Text("Server identity")
        } footer: {
            Text("A friendly name helps you recognize this server in your saved list.")
        }
    }

    private var credentialsSection: some View {
        Section {
            LoginFieldRow(systemImage: "network", title: "Address") {
                TextField("Hostname or IP address", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .host)
                    .onSubmit { focusedField = .account }
            }

            LoginFieldRow(systemImage: "person", title: "Account") {
                TextField("Username", text: $account)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .account)
                    .onSubmit { focusedField = .password }
            }

            LoginFieldRow(systemImage: "lock", title: "Password") {
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .password)
                    .onSubmit {
                        if canSubmit {
                            submit()
                        }
                    }
            }
        } header: {
            Text("Connection")
        } footer: {
            Text("Use a hostname or IP address. Include a port when your NAS does not use the default.")
        }
    }

    private var securitySection: some View {
        Section {
            Label {
                Text("Your password is stored securely on this device for automatic reconnects.")
                    .font(NasMonTypography.metadata)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "lock.shield")
                    .foregroundStyle(Color.nasMonAccent)
            }
            .padding(.vertical, NasMonSpacing.xSmall)
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var connectionErrorSection: some View {
        if case .failed(let message) = viewModel.connectionState {
            Section {
                HStack(alignment: .top, spacing: NasMonSpacing.small) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.nasMonCritical)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: NasMonSpacing.xSmall) {
                        Text("Couldn’t connect")
                            .font(NasMonTypography.cardTitle)
                            .foregroundStyle(.primary)

                        Text(message)
                            .font(NasMonTypography.supporting)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, NasMonSpacing.xSmall)
            }
            .listRowBackground(Color.nasMonCritical.opacity(0.10))
        }
    }

    private func applyPrefillValues() {
        if let prefillHost, host.isEmpty {
            host = prefillHost
        }
        if let prefillAccount, account.isEmpty {
            account = prefillAccount
        }
        if let prefillName, serverName.isEmpty {
            serverName = prefillName
        }
    }

    private func submit() {
        guard canSubmit else { return }
        focusedField = nil

        Task {
            await viewModel.login(
                host: host.trimmingCharacters(in: .whitespacesAndNewlines),
                account: account.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                name: serverName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private func cancel() {
        guard viewModel.connectionState != .loggingIn else { return }
        dismiss()
    }
}

private struct LoginFieldRow<FieldContent: View>: View {
    let systemImage: String
    let title: String
    @ViewBuilder let field: () -> FieldContent

    var body: some View {
        HStack(spacing: NasMonSpacing.small) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.nasMonAccent)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: NasMonSpacing.xxSmall) {
                Text(title)
                    .font(NasMonTypography.metadata)
                    .foregroundStyle(.secondary)

                field()
                    .font(NasMonTypography.body)
            }
        }
        .padding(.vertical, NasMonSpacing.xSmall)
    }
}

#Preview {
    NavigationStack {
        LoginView(viewModel: SessionViewModel())
    }
}
