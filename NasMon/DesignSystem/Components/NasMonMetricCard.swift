//
//  NasMonMetricCard.swift
//  NasMon
//
//  Metric surface for Dashboard values. The value uses monospaced digits so
//  polling updates do not cause the number to jump horizontally.
//

import SwiftUI

struct NasMonMetricCard: View {
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
            HStack(alignment: .top, spacing: NasMonSpacing.small) {
                VStack(alignment: .leading, spacing: NasMonSpacing.xSmall) {
                    Text(title.uppercased())
                        .font(NasMonTypography.metadata.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)

                    Text(value)
                        .font(NasMonTypography.metric)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    if let detail {
                        Text(detail)
                            .font(NasMonTypography.metadata)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: NasMonSpacing.small)

                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
            }

            if let progress {
                ProgressView(value: clampedProgress(progress))
                    .tint(tint)
                    .accessibilityLabel(Text(title))
                    .accessibilityValue(Text("\(Int(clampedProgress(progress) * 100)) percent"))
            }
        }
    }

    private func clampedProgress(_ value: Double) -> Double {
        min(max(value.isFinite ? value : 0, 0), 1)
    }
}

#Preview {
    NasMonMetricCard(
        title: "Memory",
        value: "61%",
        detail: "2.4 GB of 4 GB",
        systemImage: "memorychip",
        progress: 0.61
    )
    .padding()
    .background(Color.nasMonPageBackground)
}
