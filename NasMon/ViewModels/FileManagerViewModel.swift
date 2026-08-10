//
//  FileManagerViewModel.swift
//  NasMon
//
//  Created by Brian Li on 8/1/26.
//

import Foundation
import Observation

@Observable
final class FileManagerViewModel {

    // MARK: - Data

    /// The list of shared folders (root level).
    var shares: [DSMShare] = []
    /// The files/folders in the currently browsed path.
    var files: [DSMFile] = []
    /// The current path being browsed. `nil` means we're at the shares (root) level.
    var currentPath: String?
    var isLoading = false
    var errorMessage: String?

    // MARK: - Dependencies

    /// The active DSM client for the current session.
    var activeClient: DSMClient?

    private let sessionService = SessionService.shared

    // MARK: - Load Shares (Root)

    /// Load the list of shared folders from the NAS.
    func loadShares() async {
        guard let client = activeClient else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            shares = try await client.fetchShares()
            currentPath = nil
            files = []
        } catch is CancellationError {
            // A cancelled refresh is not a failure — the user pulled again, the
            // view went away, or the system ended the refresh control. Keep the
            // existing list and any prior error untouched.
        } catch let error as URLError where error.code == .cancelled {
            // URLSession surfaces task cancellation as .cancelled; same handling.
        } catch {
            errorMessage = sessionService.describeError(error)
        }
    }

    // MARK: - File Loading

    /// Fetch files for a path and update the folder destination's state.
    private func fetchFiles(in path: String) async {
        guard let client = activeClient else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Request additional info (size, mtime, type) so the UI can show
            // file sizes and modification times.
            files = try await client.listFiles(in: path, includeAdditionalInfo: true)
            currentPath = path
        } catch is CancellationError {
            // A cancelled refresh is not a failure — see `loadShares`.
        } catch let error as URLError where error.code == .cancelled {
            // URLSession surfaces task cancellation as .cancelled; same handling.
        } catch {
            errorMessage = sessionService.describeError(error)
        }
    }

    // MARK: - Navigation

    /// Load the contents for one folder destination in the SwiftUI navigation stack.
    func loadFolder(at path: String) async {
        await fetchFiles(in: path)
    }

    // MARK: - Reload

    /// Reload the current view (shares list or current folder).
    func reload() async {
        if currentPath == nil {
            await loadShares()
        } else if let path = currentPath {
            await fetchFiles(in: path)
        }
    }

    // MARK: - State Reset

    /// Reset state when returning to server selection.
    func reset() {
        shares = []
        files = []
        currentPath = nil
        isLoading = false
        errorMessage = nil
    }
}