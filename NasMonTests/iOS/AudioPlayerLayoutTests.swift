//
//  AudioPlayerLayoutTests.swift
//  NasMonTests
//

import CoreGraphics
import Testing
@testable import NasMon

@Suite
struct AudioPlayerLayoutTests {
    @Test func usesSideBySideControlsOnAnIPhoneLandscapeCanvas() {
        let layout = AudioPlayerLayout(
            container: CGSize(width: 844, height: 390),
            usesCompactHeight: true
        )

        #expect(layout.usesHorizontalLayout)
        #expect(layout.artworkSide <= 300)
        #expect(layout.artworkSide + (layout.horizontalPadding * 2) < 844)
    }

    @Test func keepsTheArtworkWithinThePortraitCanvas() {
        let layout = AudioPlayerLayout(
            container: CGSize(width: 393, height: 852),
            usesCompactHeight: false
        )

        #expect(!layout.usesHorizontalLayout)
        #expect(layout.artworkSide <= 345)
        #expect(layout.artworkSide >= 144)
    }
}
