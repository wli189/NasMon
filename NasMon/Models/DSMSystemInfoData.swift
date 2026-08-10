//
//  DSMSystemInfoData.swift
//  NasMon
//
//  Created by Brian Li on 7/30/26.
//

import Foundation

struct DSMSystemInfoResponse: Codable {
    let success: Bool
    let data: DSMSystemInfoData?
}

struct DSMSystemInfoData: Codable {
    let model: String?
    let cpu_clock_speed: Int?
    let cpu_cores: String?
    let cpu_family: String?
    let cpu_series: String?
    let cpu_vendor: String?
    let ram_size: Int?
    let sys_temp: Int?
    let up_time: String?
    let firmware_ver: String?
    let firmware_date: String?
    let time_zone_desc: String?

    init(
        model: String?,
        cpu_clock_speed: Int?,
        ram_size: Int?,
        sys_temp: Int?,
        up_time: String?,
        cpu_cores: String? = nil,
        cpu_family: String? = nil,
        cpu_series: String? = nil,
        cpu_vendor: String? = nil,
        firmware_ver: String? = nil,
        firmware_date: String? = nil,
        time_zone_desc: String? = nil
    ) {
        self.model = model
        self.cpu_clock_speed = cpu_clock_speed
        self.cpu_cores = cpu_cores
        self.cpu_family = cpu_family
        self.cpu_series = cpu_series
        self.cpu_vendor = cpu_vendor
        self.ram_size = ram_size
        self.sys_temp = sys_temp
        self.up_time = up_time
        self.firmware_ver = firmware_ver
        self.firmware_date = firmware_date
        self.time_zone_desc = time_zone_desc
    }

    /// Parse the raw uptime string (e.g. "91:30:58")
    /// and return a human-readable format with days, hours, and minutes.
    var formattedUptime: String {
        guard let raw = up_time, !raw.isEmpty else { return "—" }

        // Try to parse "HH:MM:SS". DSM may omit a leading zero in seconds.
        let timeOnlyPattern = #/^(\d+):(\d+):(\d+)$/#

        if let match = try? timeOnlyPattern.firstMatch(in: raw) {
            let totalHours = Int(match.1) ?? 0
            let minutes = Int(match.2) ?? 0
            let days = totalHours / 24
            let hours = totalHours % 24
            return Self.formatUptime(days: days, hours: hours, minutes: minutes)
        }

        // Fallback: return raw string when DSM changes the format.
        return raw
    }

    private static func formatUptime(days: Int, hours: Int, minutes: Int) -> String {
        var parts: [String] = []

        if days > 0 {
            parts.append("\(days) day\(days > 1 ? "s" : "")")
        }
        if hours > 0 {
            parts.append("\(hours) hour\(hours > 1 ? "s" : "")")
        }
        if minutes > 0 || parts.isEmpty {
            parts.append("\(minutes) minute\(minutes != 1 ? "s" : "")")
        }

        return parts.joined(separator: ", ")
    }
}
