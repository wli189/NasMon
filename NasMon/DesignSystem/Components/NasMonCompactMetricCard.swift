//
//  NasMonCompactMetricCard.swift
//  NasMon
//
//  Compact Dashboard metric surface for two-column layouts. Unlike
//  NasMonMetricCard, this component keeps the icon and title on one row,
//  uses a smaller value type, and allows supporting text to wrap.
//

import SwiftUI

struct NasMonCompactMetricCard: View {
    let title: String
    let value: String
    let detail: String?
    let systemImage: String
    let tint: Color
    let progress: Double?

    init(
        title: String,
        value: String,
        detail: String? = nil,
        systemImage: String,
        tint: Color = Color.nasMonAccent,
        progress: Double? = nil
    ) {
        self.title = title
        self.value = value
        self.detail = detail
        self.systemImage = systemImage
        self.tint = tint
        self.progress = progress
    }

    var body: some View {
        NasMonCard(style: .console) {
            HStack(alignment: .center, spacing: NasMonSpacing.small) {
                Text(title.uppercased())
                    .font(NasMonTypography.metadata.weight(.semibold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: NasMonSpacing.xSmall)

                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
            }

            Text(value)
                .font(NasMonTypography.metricCompact)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let detail {
                Text(detail)
                    .font(NasMonTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let progress {
                ProgressView(value: clampedProgress(progress))
                    .tint(tint)
                    .accessibilityLabel(Text(title))
                    .accessibilityValue(Text("\(Int(clampedProgress(progress) * 100)) percent"))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 144, alignment: .leading)
    }

    private func clampedProgress(_ value: Double) -> Double {
        min(max(value.isFinite ? value : 0, 0), 1)
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        NasMonCompactMetricCard(
            title: "Memory",
            value: "20%",
            detail: "1.0 GB available · 18.0 GB total",
            systemImage: "memorychip",
            progress: 0.2
        )

        NasMonCompactMetricCard(
            title: "Network",
            value: "2.0 KB/s",
            detail: "↓ 1.4 KB/s · ↑ 598 B/s",
            systemImage: "network"
        )
    }
    .padding()
    .background(Color.nasMonPageBackground)
}
