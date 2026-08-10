//
//  NasMonContentStateView.swift
//  NasMon
//
//  Shared loading, empty and recoverable error surface.
//

import SwiftUI

struct NasMonContentStateView: View {
    enum Kind {
        case loading
        case empty
        case error
        case offline
    }

    let kind: Kind
    let title: String
    let message: String?
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        kind: Kind,
        title: String,
        message: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.kind = kind
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: iconName)
        } description: {
            if let message {
                Text(message)
            }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(buttonTint)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        switch kind {
        case .loading:
            return "arrow.triangle.2.circlepath"
        case .empty:
            return "tray"
        case .error:
            return "exclamationmark.triangle"
        case .offline:
            return "wifi.slash"
        }
    }

    private var buttonTint: Color {
        switch kind {
        case .error, .offline:
            return Color.nasMonAccent
        case .loading, .empty:
            return Color.nasMonAccent
        }
    }
}

#Preview {
    NasMonContentStateView(
        kind: .error,
        title: "Could not load files",
        message: "Check the server connection and try again.",
        actionTitle: "Retry",
        action: {}
    )
}
