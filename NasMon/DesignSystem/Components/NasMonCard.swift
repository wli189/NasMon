//
//  NasMonCard.swift
//  NasMon
//
//  Generic bounded surface used by server, Dashboard and settings UI.
//

import SwiftUI

enum NasMonCardStyle {
    case standard
    case console

    var background: Color {
        switch self {
        case .standard:
            return Color.nasMonSurface
        case .console:
            return Color.nasMonSurfaceSecondary
        }
    }

    var border: Color? {
        switch self {
        case .standard:
            return nil
        case .console:
            return Color.primary.opacity(0.08)
        }
    }
}

struct NasMonCard<Content: View>: View {
    private let title: String?
    private let systemImage: String?
    private let style: NasMonCardStyle
    private let content: Content

    init(
        title: String? = nil,
        systemImage: String? = nil,
        style: NasMonCardStyle = .standard,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NasMonSpacing.medium) {
            if title != nil || systemImage != nil {
                HStack(spacing: NasMonSpacing.small) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .foregroundStyle(Color.nasMonAccent)
                            .accessibilityHidden(true)
                    }

                    if let title {
                        Text(title)
                            .font(.nasMonCardTitle)
                            .foregroundStyle(.primary)
                    }
                }
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NasMonSpacing.large)
        .nasMonSurface(
            style.background,
            cornerRadius: NasMonCornerRadius.card,
            border: style.border
        )
        .accessibilityElement(children: .contain)
    }
}

private extension Font {
    static let nasMonCardTitle = NasMonTypography.cardTitle
}

#Preview {
    VStack(spacing: 16) {
        NasMonCard(title: "Server", systemImage: "server.rack") {
            Text("DS923+")
                .font(.title3.weight(.semibold))
        }

        NasMonCard(title: "Console", systemImage: "gauge.with.dots.needle.33percent", style: .console) {
            Text("61%")
                .font(NasMonTypography.metric)
                .monospacedDigit()
        }
    }
    .padding()
    .background(Color.nasMonPageBackground)
}
