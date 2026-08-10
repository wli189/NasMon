//
//  ImagePreviewDecoderTests.swift
//  NasMonTests
//

import ImageIO
import Testing
import UIKit
@testable import NasMon

@Suite
struct ImagePreviewDecoderTests {
    /// Photos may store landscape pixel data with EXIF orientation 6 and rely
    /// on the viewer to rotate it 90 degrees clockwise. The preview decoder
    /// must preserve that display orientation instead of treating the raw
    /// pixels as upright.
    @Test func imagePreviewHonorsEXIFOrientation() throws {
        let data = try #require(jpegFixture(orientation: 6))
        let image = try #require(
            ImagePreviewDecoder.decode(data: data, isFinal: true)
        )

        #expect(image.imageOrientation == .right)
        #expect(image.size == CGSize(width: 20, height: 40))
    }


    @Test func doubleTapZoomTogglesBetweenFitAndReadableScale() {
        #expect(ImagePreviewZoom.toggledScale(from: 1) == 2)
        #expect(ImagePreviewZoom.toggledScale(from: 2) == 1)
        #expect(ImagePreviewZoom.toggledScale(from: 4) == 1)
    }

    private func jpegFixture(orientation: UInt32) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 40, height: 20),
            format: format
        )
        let sourceImage = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
            UIColor.green.setFill()
            context.fill(CGRect(x: 20, y: 0, width: 20, height: 10))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 10, width: 20, height: 10))
            UIColor.yellow.setFill()
            context.fill(CGRect(x: 20, y: 10, width: 20, height: 10))
        }
        guard let cgImage = sourceImage.cgImage else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            "public.jpeg" as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let properties = [kCGImagePropertyOrientation: orientation] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
