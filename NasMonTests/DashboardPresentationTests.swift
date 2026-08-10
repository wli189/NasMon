//
//  DashboardPresentationTests.swift
//  NasMonTests
//

import Testing
@testable import NasMon

struct DashboardPresentationTests {
    @Test func mapsDSMMonitoringDataToDashboardPresentation() {
        let presentation = DashboardPresentation(
            systemInfo: DSMSystemInfoData(
                model: "DS224+",
                cpu_clock_speed: 2000,
                ram_size: 18432,
                sys_temp: 51,
                up_time: "141:13:6",
                cpu_cores: "4",
                cpu_family: "Celeron",
                cpu_series: "J4125",
                cpu_vendor: "INTEL",
                firmware_ver: "DSM 7.3.2-86009 Update 4",
                firmware_date: "2026/06/18",
                time_zone_desc: "(GMT-06:00) Central Time"
            ),
            utilization: DSMUtilizationData(
                cpu: DSMCPUUtilization(user_load: 2, system_load: 2, other_load: 2),
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
                network: [DSMNetworkUtilization(device: "total", rx: 1_424, tx: 598)]
            ),
            isConnected: true,
            hasError: false
        )

        #expect(presentation.modelName == "DS224+")
        #expect(presentation.connectionValue == "Online")
        #expect(presentation.uptime == "5 days, 21 hours, 13 minutes")
        #expect(presentation.health.title == "Healthy")
        #expect(presentation.cpu.value == "6%")
        #expect(presentation.memory.value == "20%")
        #expect(presentation.memory.detail == "1.0 GB available · 18.0 GB total")
        #expect(presentation.disk.value == "4%")
        #expect(presentation.network.value == "2.0 KB/s")
        #expect(presentation.systemDetails.first?.value == "INTEL · Celeron · J4125 · 4 cores")
        #expect(presentation.systemDetails.first(where: { $0.id == "firmware" })?.value == "DSM 7.3.2-86009 Update 4")
    }

    @Test func reportsWaitingWhenDashboardHasNoData() {
        let presentation = DashboardPresentation(
            systemInfo: nil,
            utilization: nil,
            isConnected: false,
            hasError: false
        )

        #expect(!presentation.hasAnyData)
        #expect(presentation.health.title == "Waiting")
        #expect(presentation.connectionValue == "Disconnected")
        #expect(presentation.cpu.value == "—")
        #expect(presentation.memory.value == "—")
    }
}
