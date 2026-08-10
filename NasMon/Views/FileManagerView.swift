//
//  FileManagerView.swift
//  NasMon
//
//  Created by Brian Li on 7/30/26.
//

import SwiftUI

struct FileManagerFolderRoute: Hashable {
    let path: String
    let name: String
}

struct FileManagerNavigationRoot: View {
    @Bindable var sessionViewModel: SessionViewModel
    @State private var navigationPath: [FileManagerFolderRoute] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            FileManagerView(
                sessionViewModel: sessionViewModel,
                folderPath: nil,
                folderTitle: nil,
                navigationPath: $navigationPath
            )
            .navigationDestination(for: FileManagerFolderRoute.self) { route in
                FileManagerView(
                    sessionViewModel: sessionViewModel,
                    folderPath: route.path,
                    folderTitle: route.name,
                    navigationPath: $navigationPath
                )
            }
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.nasMonSurface, for: .navigationBar)
    }
}

struct FileManagerView: View {
    @Bindable var sessionViewModel: SessionViewModel
    @Binding private var navigationPath: [FileManagerFolderRoute]
    private let folderPath: String?
    private let folderTitle: String?
    @State private var viewModel = FileManagerViewModel()
    /// Every supported preview is presented independently from the folder
    /// navigation stack.
    @State private var selectedPreviewFile: DSMFile?
    /// Set when the user taps a file with no preview surface — shows
    /// an explanation instead of silently ignoring the tap.
    @State private var unsupportedFileMessage: String?

    init(
        sessionViewModel: SessionViewModel,
        folderPath: String?,
        folderTitle: String?,
        navigationPath: Binding<[FileManagerFolderRoute]>
    ) {
        self.sessionViewModel = sessionViewModel
        self.folderPath = folderPath
        self.folderTitle = folderTitle
        self._navigationPath = navigationPath
    }

    var body: some View {
        content
            .navigationTitle(currentFolderTitle)
            .navigationBarTitleDisplayMode(.large)
            .navigationBarBackButtonHidden(folderPath != nil)
            .toolbar {
                navigationToolbar
                refreshToolbar
            }
            .task(id: folderPath) {
                viewModel.activeClient = sessionViewModel.activeClient

                if let folderPath {
                    if viewModel.currentPath != folderPath {
                        await viewModel.loadFolder(at: folderPath)
                    }
                } else if viewModel.shares.isEmpty && viewModel.currentPath == nil {
                    await viewModel.loadShares()
                }
            }
            .onChange(of: sessionViewModel.activeClient) { _, newClient in
                viewModel.activeClient = newClient
                Task {
                    if let folderPath {
                        await viewModel.loadFolder(at: folderPath)
                    } else {
                        await viewModel.loadShares()
                    }
                }
            }
            .fullScreenCover(item: $selectedPreviewFile) { file in
                NavigationStack {
                    // Keep the route decision and the rendered preview in sync.
                    switch PreviewRouter.category(for: file) {
                    case .video:
                        VideoPlayerRouteView(file: file, client: sessionViewModel.activeClient)
                    case .audio:
                        AudioPlayerRouteView(file: file, client: sessionViewModel.activeClient)
                    case .image, .pdf, .text, .quickLook:
                        PreviewRouteView(file: file, client: sessionViewModel.activeClient)
                    case .unsupported:
                        ContentUnavailableView(
                            "Preview Unavailable",
                            systemImage: "eye.slash",
                            description: Text("This file type cannot be previewed.")
                        )
                    }
                }
            }
            .alert(
                "Cannot Preview",
                isPresented: Binding(
                    get: { unsupportedFileMessage != nil },
                    set: { if !$0 { unsupportedFileMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(unsupportedFileMessage ?? "")
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isInitialLoading {
            NasMonContentStateView(
                kind: .loading,
                title: "Loading Files",
                message: "Connecting to the NAS file service."
            )
            .padding(.horizontal, NasMonSpacing.pageHorizontal)
            .background(Color.nasMonPageBackground)
        } else if let error = viewModel.errorMessage, !hasContent {
            NasMonContentStateView(
                kind: .error,
                title: "Couldn’t Load Files",
                message: error,
                actionTitle: "Try Again",
                action: { Task { await reload() } }
            )
            .padding(.horizontal, NasMonSpacing.pageHorizontal)
            .background(Color.nasMonPageBackground)
        } else {
            fileList
        }
    }

    private var fileList: some View {
        GeometryReader { proxy in
            Group {
                if isEmpty && !viewModel.isLoading {
                    emptyState
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    filesScrollView
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.nasMonPageBackground)
        }
    }

    private var filesScrollView: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let error = viewModel.errorMessage {
                    inlineError(error)
                        .padding(.horizontal, NasMonSpacing.pageHorizontal)
                        .padding(.vertical, NasMonSpacing.small)
                }

                if viewModel.currentPath == nil {
                    ForEach(viewModel.shares) { share in
                        shareRow(share)
                    }
                } else {
                    ForEach(viewModel.files) { file in
                        fileRow(file)
                    }
                }

                if hasContent {
                    Spacer(minLength: 0)

                    itemCountBar
                        .padding(.horizontal, NasMonSpacing.pageHorizontal)
                        .padding(.vertical, NasMonSpacing.medium)
                }
            }
        }
        .refreshable {
            // `.refreshable` runs this closure in a task that SwiftUI can
            // cancel mid-flight (user pulls again, the refresh control is
            // dismissed, the view goes away). Cancelling the *spinner* would
            // tear down the in-flight URLSession request — the URL logs but the
            // response never arrives, so the list never refreshes. Spawn a
            // detached task so the fetch runs to completion regardless of what
            // the refresh control does.
            let reloadTask = Task { await reload() }
            await reloadTask.value
        }
    }

    private var emptyState: some View {
        VStack(spacing: NasMonSpacing.medium) {
            Image(systemName: "folder")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(viewModel.currentPath == nil ? "No Shared Folders" : "Folder is Empty")
                .font(NasMonTypography.cardTitle)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
    }

    private var itemCountBar: some View {
        Text(itemCountLabel)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, NasMonSpacing.large)
            .background(Color.nasMonPageBackground)
            .clipShape(.rect(cornerRadius: NasMonCornerRadius.card))
    }

    private func inlineError(_ error: String) -> some View {
        NasMonCard(style: .standard) {
            HStack(alignment: .top, spacing: NasMonSpacing.small) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.nasMonCritical)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: NasMonSpacing.xSmall) {
                    Text("Refresh Failed")
                        .font(NasMonTypography.supporting.weight(.semibold))
                    Text(error)
                        .font(NasMonTypography.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: NasMonSpacing.small)

                Button("Retry") {
                    Task { await reload() }
                }
                .buttonStyle(.bordered)
                .tint(Color.nasMonAccent)
            }
        }
    }

    // MARK: - Rows

    private func shareRow(_ share: DSMShare) -> some View {
        NavigationLink(value: FileManagerFolderRoute(path: share.path, name: share.name)) {
            rowChrome {
                HStack(spacing: NasMonSpacing.medium) {
                    fileIcon(systemName: "folder.fill", tint: .nasMonAccent)

                    VStack(alignment: .leading, spacing: NasMonSpacing.xSmall) {
                        Text(share.name)
                            .font(NasMonTypography.body)
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        if let size = share.additional?.size,
                           let mtime = share.additional?.time?.mtime {
                            Text("\(DSMFile.formatBytes(size)) · \(DSMFile.formatDate(mtime))")
                                .font(NasMonTypography.metadata)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("Shared folder")
                                .font(NasMonTypography.metadata)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: NasMonSpacing.small)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func fileRow(_ file: DSMFile) -> some View {
        if file.isdir {
            NavigationLink(value: FileManagerFolderRoute(path: file.path, name: file.name)) {
                rowChrome {
                    fileRowContent(file)
                }
            }
            .buttonStyle(.plain)
        } else {
            Button {
                switch PreviewRouter.category(for: file) {
                case .video, .audio, .image, .pdf, .text, .quickLook:
                    selectedPreviewFile = file
                case .unsupported:
                    unsupportedFileMessage = "No preview is available for \(file.name)."
                }
            } label: {
                rowChrome {
                    fileRowContent(file)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func fileRowContent(_ file: DSMFile) -> some View {
        HStack(spacing: NasMonSpacing.medium) {
            fileIcon(systemName: file.iconName, tint: file.iconColor)

            VStack(alignment: .leading, spacing: NasMonSpacing.xSmall) {
                Text(file.name)
                    .font(NasMonTypography.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(file.isdir ? "Folder" : "\(file.formattedSize) · \(file.formattedModifiedDate)")
                    .font(NasMonTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: NasMonSpacing.small)

            if file.isdir {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Open folder")
            }
        }
        .frame(minHeight: NasMonSpacing.minimumTapTarget, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func rowChrome<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, NasMonSpacing.pageHorizontal)
            .padding(.vertical, NasMonSpacing.small)
            .overlay(alignment: .bottomLeading) {
                // Use an explicit horizontal shape. `Divider` can infer a
                // vertical orientation when it receives an HStack-sized
                // proposal from a NavigationLink label.
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
                    .padding(.leading, NasMonSpacing.pageHorizontal + 40 + NasMonSpacing.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
            }
    }

    private func fileIcon(systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.title3)
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(tint.opacity(0.12), in: .rect(cornerRadius: NasMonCornerRadius.control))
            .accessibilityHidden(true)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if folderPath == nil {
                Button {
                    sessionViewModel.returnToServerSelection()
                } label: {
                    Label("Servers", systemImage: "server.rack")
                }
            } else {
                pathNavigationMenu
            }
        }
    }

    private var pathNavigationMenu: some View {
        Menu {
            // Ancestors only — the current folder is already on screen, so
            // showing it in the jump menu is redundant. `dropLast()` removes
            // the current route, leaving the path up to its parent. The
            // enumerated index equals the route's position in the full path,
            // so tapping the ancestor at `index` keeps `[0...index]`.
            ForEach(Array(navigationPath.dropLast().enumerated()), id: \.element) { index, route in
                Button {
                    navigationPath.removeLast(navigationPath.count - index - 1)
                } label: {
                    Text(route.name)
                }
            }

            Button {
                navigationPath.removeAll()
            } label: {
                Text("Shared Folders")
            }
        } label: {
            Label("Back", systemImage: "chevron.backward")
        } primaryAction: {
            if !navigationPath.isEmpty {
                navigationPath.removeLast()
            }
        }
    }

    @ToolbarContentBuilder
    private var refreshToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await reload() }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .disabled(viewModel.isLoading)
        }
    }

    // MARK: - Helpers

    private var hasContent: Bool {
        viewModel.currentPath == nil ? !viewModel.shares.isEmpty : !viewModel.files.isEmpty
    }

    private var isInitialLoading: Bool {
        viewModel.isLoading && !hasContent && viewModel.errorMessage == nil
    }

    private var isEmpty: Bool {
        viewModel.currentPath == nil ? viewModel.shares.isEmpty : viewModel.files.isEmpty
    }

    private var currentFolderTitle: String {
        if let folderTitle {
            return folderTitle
        }
        guard let currentPath = viewModel.currentPath else {
            return "File Management"
        }
        return folderName(for: currentPath)
    }

    private var itemCountLabel: String {
        let count = viewModel.currentPath == nil ? viewModel.shares.count : viewModel.files.count
        return "\(count) \(count == 1 ? "item" : "items")"
    }

    private func folderName(for path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? path : name
    }

    private func reload() async {
        await viewModel.reload()
    }
}

#Preview {
    FileManagerNavigationRoot(sessionViewModel: SessionViewModel())
}
