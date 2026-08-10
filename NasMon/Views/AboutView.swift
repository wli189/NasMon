//
//  AboutView.swift
//  NasMon
//
//  App information and third-party dependencies, presented from the "…"
//  menu on the server list.
//

import SwiftUI

/// App version, OS support, and the third-party libraries NasMon links against.
struct AboutView: View {
    var body: some View {
        List {
            Section {
                appHeader
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(
                        EdgeInsets(
                            top: NasMonSpacing.large,
                            leading: NasMonSpacing.large,
                            bottom: NasMonSpacing.large,
                            trailing: NasMonSpacing.large
                        )
                    )
            }

            Section("App") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Build", value: buildNumber)
            }

            Section {
                dependencyRow(
                    "Runestone",
                    version: "0.5.2",
                    role: "Text editor / syntax highlighting for text previews",
                    url: "https://github.com/simonbs/Runestone"
                )
                dependencyRow(
                    "TreeSitter",
                    version: "0.20.9",
                    role: "Incremental parsing engine used by Runestone",
                    url: "https://github.com/tree-sitter/tree-sitter"
                )
                dependencyRow(
                    "TreeSitterLanguages",
                    version: "0.1.10",
                    role: "Grammar definitions bundled with TreeSitter",
                    url: "https://github.com/simonbs/TreeSitterLanguages"
                )
            } header: {
                Text("Third-Party Libraries")
            } footer: {
                Text("NasMon is an independent client and is not affiliated with Synology.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.nasMonPageBackground)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appHeader: some View {
        VStack(spacing: NasMonSpacing.small) {
            Image(systemName: "server.rack")
                .font(.system(size: 44))
                .foregroundStyle(Color.nasMonAccent)
                .padding(NasMonSpacing.large)
                .background(Color.nasMonAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: NasMonCornerRadius.largeCard))

            Text("NasMon")
                .font(NasMonTypography.pageTitle)

            Text("Synology NAS monitor & file browser")
                .font(NasMonTypography.supporting)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    private func dependencyRow(_ name: String, version: String, role: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: NasMonSpacing.xSmall) {
            HStack(spacing: NasMonSpacing.small) {
                Text(name)
                    .font(.body.weight(.semibold))
                Text("v\(version)")
                    .font(NasMonTypography.metadata)
                    .foregroundStyle(.secondary)
            }
            Text(role)
                .font(NasMonTypography.supporting)
                .foregroundStyle(.secondary)

            Link(destination: URL(string: url)!) {
                Label(url.replacingOccurrences(of: "https://github.com/", with: ""), systemImage: "arrow.up.right.square")
                    .font(NasMonTypography.metadata)
            }
            .tint(Color.nasMonAccent)
        }
        .padding(.vertical, NasMonSpacing.xSmall)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
