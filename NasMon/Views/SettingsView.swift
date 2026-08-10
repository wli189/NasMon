//
//  SettingsView.swift
//  NasMon
//
//  In-app settings, presented from the "…" menu on the server list.
//  Currently hosts the preview cache management.
//

import SwiftUI

/// In-app settings surface. Owns the preview cache management controls.
struct SettingsView: View {
    /// Whether the preview cache was just cleared (shows a brief confirmation).
    @State private var didClearCache = false

    var body: some View {
        List {
            Section {
                NasMonCard(style: .standard) {
                    cacheInfo
                }
                .settingsCardRowStyle()

                Button(role: .destructive) {
                    PreviewCache.clearAll()
                    didClearCache = true
                } label: {
                    Label("Clear Preview Cache", systemImage: "trash")
                        .font(NasMonTypography.supporting)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, NasMonSpacing.large)
                        .padding(.vertical, NasMonSpacing.large)
                        .background(Color.nasMonSurface, in: RoundedRectangle(cornerRadius: NasMonCornerRadius.card))
                }
                .buttonStyle(.plain)
                .settingsCardRowStyle()
                .accessibilityHint("Removes all downloaded preview files from this device.")
            } footer: {
                Text("Removes downloaded image, PDF, and text preview files. Cached files are stored on this device so previews open without re-downloading. This does not remove saved servers or login information.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.nasMonPageBackground)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Cache Cleared", isPresented: $didClearCache) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Downloaded preview files were removed from this device.")
        }
    }

    private var cacheInfo: some View {
        VStack(alignment: .leading, spacing: NasMonSpacing.small) {
            Label("Preview Cache", systemImage: "internaldrive")
                .font(NasMonTypography.cardTitle)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: NasMonSpacing.xSmall) {
                LabeledContent("Used", value: ByteCountFormatter.string(
                    fromByteCount: PreviewCache.currentBytes,
                    countStyle: .file
                ))
                LabeledContent("Limit", value: ByteCountFormatter.string(
                    fromByteCount: PreviewCache.totalQuota,
                    countStyle: .file
                ))
            }
            .font(NasMonTypography.supporting)
            .foregroundStyle(.secondary)
        }
    }
}

private extension View {
    /// Shared row treatment so the cache-info card and the clear-cache action
    /// align with each other (and the wider card surface) instead of each row
    /// following the system row inset.
    func settingsCardRowStyle() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowInsets(
                EdgeInsets(
                    top: NasMonSpacing.medium,
                    leading: NasMonSpacing.pageHorizontal,
                    bottom: NasMonSpacing.medium,
                    trailing: NasMonSpacing.pageHorizontal
                )
            )
            .listRowSeparator(.hidden)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
