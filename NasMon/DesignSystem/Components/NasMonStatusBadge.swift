//
//  NasMonStatusBadge.swift
//  NasMon
//
//  Compact status indicator that always combines color, icon and text.
//

import SwiftUI

struct NasMonStatusBadge: View {
    let title: String
    let systemImage: String
    let tint: Color

    init(
        _ title: String,
        systemImage: String,
        tint: Color
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: NasMonSpacing.xSmall) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(NasMonTypography.status)
        .foregroundStyle(tint)
        .padding(.horizontal, NasMonSpacing.small)
        .padding(.vertical, NasMonSpacing.xSmall)
        .background(tint.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

extension NasMonStatusBadge {
    static var online: NasMonStatusBadge {
        NasMonStatusBadge(
            "Online",
            systemImage: "checkmark.circle.fill",
            tint: Color.nasMonOnline
        )
    }

    static var warning: NasMonStatusBadge {
        NasMonStatusBadge(
            "Warning",
            systemImage: "exclamationmark.triangle.fill",
            tint: Color.nasMonWarning
        )
    }

    static var offline: NasMonStatusBadge {
        NasMonStatusBadge(
            "Offline",
            systemImage: "xmark.circle.fill",
            tint: Color.nasMonCritical
        )
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 10) {
        NasMonStatusBadge.online
        NasMonStatusBadge.warning
        NasMonStatusBadge.offline
    }
    .padding()
}
