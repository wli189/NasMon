//
//  DSMUtilizationData.swift
//  NasMon
//
//  Created by Brian Li on 7/30/26.
//

import Foundation

struct DSMUtilizationResponse: Codable {
    let success: Bool
    let data: DSMUtilizationData?
}

struct DSMUtilizationData: Codable {
    let cpu: DSMCPUUtilization?
    let memory: DSMMemoryUtilization?
    let disk: DSMDiskUtilization?
    let network: [DSMNetworkUtilization]?
}

struct DSMCPUUtilization: Codable {
    let user_load: Int?
    let system_load: Int?
    let other_load: Int?
    let device: String?

    init(
        user_load: Int?,
        system_load: Int?,
        other_load: Int? = nil,
        device: String? = nil
    ) {
        self.user_load = user_load
        self.system_load = system_load
        self.other_load = other_load
        self.device = device
    }
}

struct DSMMemoryUtilization: Codable {
    /// DSM returns this field as a percentage, not a byte count.
    let real_usage: Int?
    let total_real: Int?
    let avail_real: Int?
    let memory_size: Int?
    let swap_usage: Int?
    let total_swap: Int?

    init(
        real_usage: Int?,
        total_real: Int?,
        avail_real: Int? = nil,
        memory_size: Int? = nil,
        swap_usage: Int? = nil,
        total_swap: Int? = nil
    ) {
        self.real_usage = real_usage
        self.total_real = total_real
        self.avail_real = avail_real
        self.memory_size = memory_size
        self.swap_usage = swap_usage
        self.total_swap = total_swap
    }
}

struct DSMDiskUtilization: Codable {
    let disk: [DSMStorageDeviceUtilization]?
    let total: DSMStorageDeviceUtilization?
}

struct DSMStorageDeviceUtilization: Codable {
    let device: String?
    let display_name: String?
    let utilization: Int?
    let read_byte: Int?
    let write_byte: Int?
    let type: String?
}

struct DSMNetworkUtilization: Codable {
    let device: String?
    let rx: Int?
    let tx: Int?
}
