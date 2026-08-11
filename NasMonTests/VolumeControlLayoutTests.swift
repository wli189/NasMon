//
//  VolumeControlLayoutTests.swift
//  NasMonTests
//

import CoreGraphics
import Testing
@testable import NasMon

struct VolumeControlLayoutTests {
    @Test func iOS18ToolbarWidthStaysAtExpandedWidthWhileMaskCollapses() {
        let layout = VolumeControlLayout()

        #expect(layout.expandedWidth == 142)
        #expect(layout.revealedWidth(isExpanded: false) == layout.controlHeight)
        #expect(layout.revealedWidth(isExpanded: true) == layout.expandedWidth)
    }
}
