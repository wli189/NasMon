//
//  DashboardView.swift
//  NasMon
//
//  Created by Brian Li on 7/30/26.
//

import SwiftUI

struct DashboardView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var viewModel: DashboardViewModel
    @Bindable var sessionViewModel: SessionViewModel
    @State private var showRebootConfirmation = false
    @State private var showShutdownConfirmation = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: NasMonSpacing.xLarge) {
                serverOverview

                if presentation.hasAnyData {
                    utilizationSection
                    hostDetailsSection
                } else {
                    emptyState
                }

                if let error = viewModel.actionError {
                    errorState(error)
                }

                serverActions
                updateStatus
            }
            .padding(.horizontal, NasMonSpacing.pageHorizontal)
            .padding(.vertical, NasMonSpacing.xLarge)
        }
        .background(Color.nasMonPageBackground.ignoresSafeArea())
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    sessionViewModel.returnToServerSelection()
                } label: {
                    Label("Servers", systemImage: "server.rack")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.manualRefresh() }
                } label: {
                    if viewModel.isManualRefreshing {
                        ProgressView()
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(viewModel.isManualRefreshing || viewModel.isPerformingAction)
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
        .alert("Reboot NAS", isPresented: $showRebootConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reboot", role: .destructive) {
                Task { await viewModel.reboot() }
            }
        } message: {
            Text("Are you sure you want to reboot the NAS? This will temporarily disconnect all services.")
        }
        .alert("Shutdown NAS", isPresented: $showShutdownConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Shutdown", role: .destructive) {
                Task { await viewModel.shutdown() }
            }
        } message: {
            Text("Are you sure you want to shut down the NAS? This will power off the device and all services will stop.")
        }
    }

    // MARK: - Overview

    private var serverOverview: some View {
        VStack(alignment: .leading, spacing: NasMonSpacing.medium) {
            sectionHeading("Server Overview", systemImage: "server.rack")

            NasMonCard {
                HStack(alignment: .top, spacing: NasMonSpacing.medium) {
                    VStack(alignment: .leading, spacing: NasMonSpacing.xSmall) {
                        Text(presentation.modelName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("System health and live utilization")
                            .font(NasMonTypography.supporting)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: NasMonSpacing.small)

                    healthBadge
                }

                Divider()

                overviewRow(
                    title: "Connection",
                    value: presentation.connectionValue,
                    systemImage: "network"
                )
                overviewRow(
                    title: "Uptime",
                    value: presentation.uptime,
                    systemImage: "clock"
                )
            }
        }
    }

    private var healthBadge: NasMonStatusBadge {
        let health = presentation.health
        return NasMonStatusBadge(
            health.title,
            systemImage: health.systemImage,
            tint: health.tone.map(color(for:)) ?? .secondary
        )
    }

    private func overviewRow(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: NasMonSpacing.small) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.nasMonAccent)
                .frame(width: 20)
                .accessibilityHidden(true)

            Text(title)
                .font(NasMonTypography.supporting)
                .foregroundStyle(.secondary)

            Spacer(minLength: NasMonSpacing.small)

            Text(value)
                .font(NasMonTypography.supporting.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Metrics

    private var utilizationSection: some View {
        VStack(alignment: .leading, spacing: NasMonSpacing.medium) {
            sectionHeading("Live Utilization", systemImage: "gauge.with.dots.needle.33percent")

            LazyVGrid(columns: metricColumns, spacing: NasMonSpacing.medium) {
                compactMetricCard(presentation.cpu, title: "CPU", systemImage: "cpu")
                compactMetricCard(presentation.memory, title: "Memory", systemImage: "memorychip")
                compactMetricCard(presentation.temperature, title: "Temperature", systemImage: "thermometer.medium")
                compactMetricCard(presentation.disk, title: "Disk", systemImage: "internaldrive")

                if dynamicTypeSize.isAccessibilitySize {
                    networkMetricCard
                } else {
                    networkMetricCard
                        .gridCellColumns(2)
                }
            }
        }
    }

    private var networkMetricCard: some View {
        compactMetricCard(presentation.network, title: "Network", systemImage: "network")
    }

    private func compactMetricCard(
        _ metric: DashboardPresentation.Metric,
        title: String,
        systemImage: String
    ) -> some View {
        NasMonCompactMetricCard(
            title: title,
            value: metric.value,
            detail: metric.detail,
            systemImage: systemImage,
            tint: color(for: metric.tone),
            progress: metric.progress
        )
    }

    private var hostDetailsSection: some View {
        VStack(alignment: .leading, spacing: NasMonSpacing.medium) {
            sectionHeading("System Details", systemImage: "info.circle")

            NasMonCard(style: .standard) {
                ForEach(presentation.systemDetails) { detail in
                    if detail.id != presentation.systemDetails.first?.id {
                        Divider()
                    }
                    detailRow(detail.title, value: detail.value)
                }
            }
        }
    }

    private func sectionHeading(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(NasMonTypography.cardTitle)
            .foregroundStyle(.primary)
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(spacing: NasMonSpacing.small) {
            Text(title)
                .font(NasMonTypography.supporting)
                .foregroundStyle(.secondary)

            Spacer(minLength: NasMonSpacing.small)

            Text(value)
                .font(NasMonTypography.supporting.weight(.medium))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - State and actions

    private var emptyState: some View {
        NasMonCard(style: .standard) {
            NasMonContentStateView(
                kind: viewModel.isRefreshing ? .loading : .empty,
                title: viewModel.isRefreshing ? "Loading Dashboard" : "No Dashboard Data",
                message: viewModel.isRefreshing
                    ? "Waiting for the first system update."
                    : "Pull to refresh and try loading the NAS metrics again.",
                actionTitle: viewModel.isRefreshing ? nil : "Refresh",
                action: viewModel.isRefreshing ? nil : {
                    Task { await viewModel.manualRefresh() }
                }
            )
            .frame(minHeight: 180)
        }
    }

    private func errorState(_ error: String) -> some View {
        NasMonCard(style: .standard) {
            Label("Dashboard Update Failed", systemImage: "exclamationmark.triangle.fill")
                .font(NasMonTypography.cardTitle)
                .foregroundStyle(Color.nasMonCritical)

            Text(error)
                .font(NasMonTypography.supporting)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Try Again") {
                Task { await viewModel.manualRefresh() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.nasMonAccent)
            .frame(minHeight: NasMonSpacing.minimumTapTarget)
        }
    }

    private var updateStatus: some View {
        HStack(spacing: NasMonSpacing.small) {
            if viewModel.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "clock")
                    .accessibilityHidden(true)
            }

            if let lastUpdated = viewModel.lastUpdated {
                Text("Updated \(lastUpdated.formatted(date: .omitted, time: .standard))")
            } else if viewModel.isRefreshing {
                Text("Updating dashboard…")
            } else {
                Text("Not updated yet")
            }
        }
        .font(NasMonTypography.metadata)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var serverActions: some View {
        VStack(alignment: .leading, spacing: NasMonSpacing.medium) {
            sectionHeading("Server Operations", systemImage: "exclamationmark.triangle")

            NasMonCard {
                Button(role: .destructive) {
                    showRebootConfirmation = true
                } label: {
                    actionRow(
                        title: "Reboot NAS",
                        subtitle: "Restart the device and disconnect services",
                        systemImage: "restart",
                        tint: .nasMonCritical
                    )
                }
                .disabled(viewModel.isPerformingAction)
                .buttonStyle(.plain)

                Divider()

                Button(role: .destructive) {
                    showShutdownConfirmation = true
                } label: {
                    actionRow(
                        title: "Shut Down NAS",
                        subtitle: "Power off the device and stop all services",
                        systemImage: "power",
                        tint: .nasMonCritical
                    )
                }
                .disabled(viewModel.isPerformingAction)
                .buttonStyle(.plain)
            }
        }
    }

    private func actionRow(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: NasMonSpacing.small) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: NasMonSpacing.xxSmall) {
                Text(title)
                    .font(NasMonTypography.supporting.weight(.medium))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(NasMonTypography.metadata)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: NasMonSpacing.small)
        }
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: - Derived values

    private var metricColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }

        return [
            GridItem(.flexible(), spacing: NasMonSpacing.medium),
            GridItem(.flexible(), spacing: NasMonSpacing.medium)
        ]
    }

    private var presentation: DashboardPresentation {
        DashboardPresentation(
            systemInfo: viewModel.systemInfo,
            utilization: viewModel.utilization,
            isConnected: viewModel.activeClient != nil,
            hasError: viewModel.actionError != nil
        )
    }

    private func color(for tone: DashboardPresentation.Tone) -> Color {
        switch tone {
        case .healthy:
            return .nasMonOnline
        case .accent:
            return .nasMonAccent
        case .warning:
            return .nasMonWarning
        case .critical:
            return .nasMonCritical
        }
    }
}

#Preview {
    NavigationStack {
        let vm = DashboardViewModel()
        vm.activeClient = DSMClient(host: "192.168.1.10", port: 5001)
        vm.systemInfo = DSMSystemInfoData(
            model: "DS224+",
            cpu_clock_speed: 2000,
            ram_size: 18432,
            sys_temp: 51,
            up_time: "141:13:6",
            cpu_cores: "4",
            cpu_family: "Celeron",
            cpu_series: "J4125",
            firmware_ver: "DSM 7.3.2-86009 Update 4",
            firmware_date: "2026/06/18",
            time_zone_desc: "(GMT-06:00) Central Time"
        )
        vm.utilization = DSMUtilizationData(
            cpu: DSMCPUUtilization(
                user_load: 2,
                system_load: 2,
                other_load: 2
            ),
            memory: DSMMemoryUtilization(
                real_usage: 20,
                total_real: 18_264_208,
                avail_real: 1_063_420,
                memory_size: 18_874_368,
                swap_usage: 1
            ),
            disk: DSMDiskUtilization(
                disk: nil,
                total: DSMStorageDeviceUtilization(
                    device: "total",
                    display_name: nil,
                    utilization: 4,
                    read_byte: 0,
                    write_byte: 1_706,
                    type: nil
                )
            ),
            network: [
                DSMNetworkUtilization(device: "total", rx: 1_424, tx: 598)
            ]
        )
        return DashboardView(viewModel: vm, sessionViewModel: SessionViewModel())
    }
}
