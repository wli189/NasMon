//
//  DashboardPresentation.swift
//  NasMon
//
//  Pure presentation model for Dashboard data. It keeps DSM-specific field
//  interpretation, formatting and health rules out of the SwiftUI View.
//

import Foundation

struct DashboardPresentation {
    enum Tone {
        case healthy
        case accent
        case warning
        case critical
    }

    struct Metric {
        let value: String
        let detail: String?
        let progress: Double?
        let tone: Tone
    }

    struct Detail: Identifiable {
        let id: String
        let title: String
        let value: String
    }

    struct Health {
        let title: String
        let systemImage: String
        let tone: Tone?
    }

    let modelName: String
    let connectionValue: String
    let uptime: String
    let health: Health
    let hasAnyData: Bool
    let cpu: Metric
    let memory: Metric
    let temperature: Metric
    let disk: Metric
    let network: Metric
    let systemDetails: [Detail]

    init(
        systemInfo: DSMSystemInfoData?,
        utilization: DSMUtilizationData?,
        isConnected: Bool,
        hasError: Bool
    ) {
        let hasAnyData = systemInfo != nil || utilization != nil
        let cpuLoad = Self.cpuLoad(from: utilization?.cpu)
        let memoryUsageRatio = Self.memoryUsageRatio(from: utilization?.memory)
        let diskUtilization = utilization?.disk?.total?.utilization.map(Double.init)
        let temperature = systemInfo?.sys_temp.map(Double.init)

        self.modelName = systemInfo?.model ?? "NAS Server"
        self.connectionValue = hasError && !hasAnyData
            ? "Needs attention"
            : isConnected ? "Online" : "Disconnected"
        self.uptime = systemInfo?.formattedUptime ?? "—"
        self.hasAnyData = hasAnyData
        self.health = Self.makeHealth(
            hasAnyData: hasAnyData,
            temperature: temperature,
            cpu: cpuLoad,
            memory: memoryUsageRatio.map { $0 * 100 },
            disk: diskUtilization
        )

        self.cpu = Metric(
            value: cpuLoad.map { "\(Int($0.rounded()))%" } ?? "—",
            detail: Self.cpuDetail(from: utilization?.cpu),
            progress: cpuLoad.map { $0 / 100 },
            tone: Self.tone(for: cpuLoad, warningAt: 70, criticalAt: 90)
        )
        self.memory = Metric(
            value: memoryUsageRatio.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
            detail: Self.memoryDetail(from: utilization?.memory),
            progress: memoryUsageRatio,
            tone: Self.tone(
                for: memoryUsageRatio.map { $0 * 100 },
                warningAt: 70,
                criticalAt: 90
            )
        )
        self.temperature = Metric(
            value: systemInfo?.sys_temp.map { "\($0)°C" } ?? "—",
            detail: Self.temperatureDetail(from: systemInfo?.sys_temp),
            progress: systemInfo?.sys_temp.map { min(max(Double($0) / 100, 0), 1) },
            tone: Self.tone(for: temperature, warningAt: 65, criticalAt: 75)
        )
        self.disk = Metric(
            value: diskUtilization.map { "\(Int($0.rounded()))%" } ?? "—",
            detail: Self.diskDetail(from: utilization?.disk?.total),
            progress: diskUtilization.map { min(max($0 / 100, 0), 1) },
            tone: Self.tone(for: diskUtilization, warningAt: 70, criticalAt: 90)
        )
        self.network = Self.networkMetric(from: utilization?.network)
        self.systemDetails = Self.makeSystemDetails(systemInfo: systemInfo)
    }

    // MARK: - CPU

    private static func cpuLoad(from cpu: DSMCPUUtilization?) -> Double? {
        guard let cpu else { return nil }
        guard cpu.user_load != nil || cpu.system_load != nil || cpu.other_load != nil else {
            return nil
        }

        let user = Double(cpu.user_load ?? 0)
        let system = Double(cpu.system_load ?? 0)
        let other = Double(cpu.other_load ?? 0)
        return min(max(user + system + other, 0), 100)
    }

    private static func cpuDetail(from cpu: DSMCPUUtilization?) -> String? {
        guard let cpu,
              cpu.user_load != nil || cpu.system_load != nil || cpu.other_load != nil else {
            return nil
        }

        return "User \(cpu.user_load ?? 0)% · System \(cpu.system_load ?? 0)% · Other \(cpu.other_load ?? 0)%"
    }

    // MARK: - Memory

    /// DSM's `real_usage` is already a percentage. `total_real` is a memory
    /// size in KiB and must not be used as the denominator for this value.
    private static func memoryUsageRatio(from memory: DSMMemoryUtilization?) -> Double? {
        guard let usage = memory?.real_usage else { return nil }
        return min(max(Double(usage) / 100, 0), 1)
    }

    private static func memoryDetail(from memory: DSMMemoryUtilization?) -> String? {
        guard let memory else { return nil }

        var parts: [String] = []
        if let available = memory.avail_real {
            parts.append("\(formattedMemory(available)) available")
        }
        if let total = memory.memory_size ?? memory.total_real {
            parts.append("\(formattedMemory(total)) total")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Disk and network

    private static func diskDetail(from disk: DSMStorageDeviceUtilization?) -> String? {
        guard let disk,
              disk.read_byte != nil || disk.write_byte != nil else { return nil }
        return "Read \(formattedRate(disk.read_byte)) · Write \(formattedRate(disk.write_byte))"
    }

    private static func networkMetric(from network: [DSMNetworkUtilization]?) -> Metric {
        let total = network?.first(where: { $0.device == "total" }) ?? network?.first
        let hasRate = total?.rx != nil || total?.tx != nil

        guard let total, hasRate else {
            return Metric(value: "—", detail: nil, progress: nil, tone: .accent)
        }

        let rx = total.rx ?? 0
        let tx = total.tx ?? 0
        return Metric(
            value: formattedRate(rx + tx),
            detail: "↓ \(formattedRate(total.rx)) · ↑ \(formattedRate(total.tx))",
            progress: nil,
            tone: .accent
        )
    }

    // MARK: - System details

    private static func makeSystemDetails(systemInfo: DSMSystemInfoData?) -> [Detail] {
        [
            Detail(id: "processor", title: "Processor", value: processorDescription(from: systemInfo)),
            Detail(
                id: "cpu-clock",
                title: "CPU clock",
                value: systemInfo?.cpu_clock_speed.map { "\($0) MHz" } ?? "—"
            ),
            Detail(
                id: "installed-ram",
                title: "Installed RAM",
                value: systemInfo?.ram_size.map { "\($0) MB" } ?? "—"
            ),
            Detail(id: "firmware", title: "Firmware", value: systemInfo?.firmware_ver ?? "—"),
            Detail(id: "time-zone", title: "Time zone", value: systemInfo?.time_zone_desc ?? "—")
        ]
    }

    private static func processorDescription(from systemInfo: DSMSystemInfoData?) -> String {
        var parts: [String] = []
        for component in [
            systemInfo?.cpu_vendor,
            systemInfo?.cpu_family,
            systemInfo?.cpu_series
        ]
        .compactMap({ $0 })
        where !parts.contains(component) {
            parts.append(component)
        }

        if let coreCount = systemInfo?.cpu_cores {
            parts.append("\(coreCount) cores")
        }

        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private static func temperatureDetail(from temperature: Int?) -> String? {
        guard let temperature else { return nil }
        if temperature >= 75 { return "Critical temperature" }
        if temperature >= 65 { return "Elevated temperature" }
        return "Within normal range"
    }

    // MARK: - Health and formatting

    private static func makeHealth(
        hasAnyData: Bool,
        temperature: Double?,
        cpu: Double?,
        memory: Double?,
        disk: Double?
    ) -> Health {
        guard hasAnyData else {
            return Health(title: "Waiting", systemImage: "ellipsis.circle.fill", tone: nil)
        }

        let temperature = temperature ?? 0
        let cpu = cpu ?? 0
        let memory = memory ?? 0
        let disk = disk ?? 0

        if temperature >= 75 || cpu >= 90 || memory >= 90 || disk >= 90 {
            return Health(title: "Critical", systemImage: "xmark.octagon.fill", tone: .critical)
        }
        if temperature >= 65 || cpu >= 70 || memory >= 70 || disk >= 70 {
            return Health(title: "Warning", systemImage: "exclamationmark.triangle.fill", tone: .warning)
        }
        return Health(title: "Healthy", systemImage: "checkmark.circle.fill", tone: .healthy)
    }

    private static func tone(for value: Double?, warningAt: Double, criticalAt: Double) -> Tone {
        guard let value else { return .accent }
        if value >= criticalAt { return .critical }
        if value >= warningAt { return .warning }
        return .accent
    }

    private static func formattedMemory(_ kib: Int) -> String {
        let gib = Double(kib) / 1_048_576
        if gib >= 1 {
            return "\(gib.formatted(.number.precision(.fractionLength(1)))) GB"
        }
        let mib = Double(kib) / 1_024
        return "\(mib.formatted(.number.precision(.fractionLength(0)))) MB"
    }

    private static func formattedRate(_ bytesPerSecond: Int?) -> String {
        formattedRate(bytesPerSecond ?? 0)
    }

    private static func formattedRate(_ bytesPerSecond: Int) -> String {
        let bytes = Double(max(bytesPerSecond, 0))
        if bytes >= 1_048_576 {
            return "\((bytes / 1_048_576).formatted(.number.precision(.fractionLength(1)))) MB/s"
        }
        if bytes >= 1_024 {
            return "\((bytes / 1_024).formatted(.number.precision(.fractionLength(1)))) KB/s"
        }
        return "\(Int(bytes)) B/s"
    }
}
