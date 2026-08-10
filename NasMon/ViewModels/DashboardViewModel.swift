//
//  DashboardViewModel.swift
//  NasMon
//
//  Created by Brian Li on 7/30/26.
//

import Foundation
import Observation

@Observable
final class DashboardViewModel {

    // MARK: - Data

    var systemInfo: DSMSystemInfoData?
    var utilization: DSMUtilizationData?
    var isRefreshing = false
    var isManualRefreshing = false
    var isPerformingAction = false
    var lastUpdated: Date?
    var actionError: String?

    // MARK: - Dependencies

    /// The active DSM client for the current session.
    var activeClient: DSMClient?

    private let sessionService = SessionService.shared
    private var pollTask: Task<Void, Never>?

    // MARK: - Refresh

    func refresh() async {
        guard let client = activeClient else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            async let infoTask = client.fetchSystemInfo()
            async let utilTask = client.fetchUtilization()
            let (info, util) = try await (infoTask, utilTask)

            self.systemInfo = info
            self.utilization = util
            self.lastUpdated = Date()
        } catch {
            actionError = sessionService.describeError(error)
        }
    }

    // MARK: - Manual Refresh

    /// Trigger a manual refresh. Shows loading state on the Refresh button.
    func manualRefresh() async {
        isManualRefreshing = true
        defer { isManualRefreshing = false }
        await refresh()
    }

    // MARK: - Polling

    func startPolling(interval: TimeInterval = 5.0) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            // refresh immediately
            if let self, !Task.isCancelled {
                await self.refresh()
            }
            // refresh every interval seconds
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { break }
                await self.refresh()
            }
        }
    }

    // MARK: - Stop Polling

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - NAS Actions

    /// Reboot the NAS.
    func reboot() async {
        guard let client = activeClient else { return }
        isPerformingAction = true
        actionError = nil
        defer { isPerformingAction = false }

        do {
            try await client.reboot()
        } catch {
            actionError = sessionService.describeError(error)
        }
    }

    /// Shutdown the NAS.
    func shutdown() async {
        guard let client = activeClient else { return }
        isPerformingAction = true
        actionError = nil
        defer { isPerformingAction = false }

        do {
            try await client.shutdown()
        } catch {
            actionError = sessionService.describeError(error)
        }
    }

    // MARK: - State Reset

    /// Reset dashboard state when returning to server selection.
    func reset() {
        pollTask?.cancel()
        pollTask = nil
        systemInfo = nil
        utilization = nil
        actionError = nil
        isRefreshing = false
        isManualRefreshing = false
        isPerformingAction = false
        lastUpdated = nil
    }
}