//
//  ImagePreviewDecoder.swift
//  NasMon
//
//  Decodes complete or incrementally downloaded image data for the custom
//  image preview surface while preserving the source's display orientation.
//

import Foundation
import ImageIO
import UIKit

enum ImagePreviewDecoder {
    static func decode(data: Data, isFinal: Bool) -> UIImage? {
        guard !data.isEmpty else { return nil }

        let source = CGImageSourceCreateIncremental(nil)
        CGImageSourceUpdateData(source, data as CFData, isFinal)
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        return UIImage(
            cgImage: cgImage,
            scale: 1,
            orientation: imageOrientation(from: source)
        )
    }

    private static func imageOrientation(from source: CGImageSource) -> UIImage.Orientation {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let rawValue = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value,
            let orientation = CGImagePropertyOrientation(rawValue: rawValue)
        else {
            return .up
        }

        switch orientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        case .left: return .left
        @unknown default: return .up
        }
    }
}
