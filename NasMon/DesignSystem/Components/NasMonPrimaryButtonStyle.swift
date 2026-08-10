//
//  NasMonPrimaryButtonStyle.swift
//  NasMon
//
//  Shared primary action treatment. The style keeps the button behavior
//  platform-native while centralizing NasMon's visual treatment.
//

import SwiftUI

struct NasMonPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(minHeight: NasMonSpacing.minimumTapTarget)
            .padding(.horizontal, NasMonSpacing.medium)
            .background(Color.nasMonAccent)
            .clipShape(.rect(cornerRadius: NasMonCornerRadius.control))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == NasMonPrimaryButtonStyle {
    static var nasMonPrimary: NasMonPrimaryButtonStyle { .init() }
}
