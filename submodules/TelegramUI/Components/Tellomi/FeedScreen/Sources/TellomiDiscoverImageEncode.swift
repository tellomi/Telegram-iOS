import Foundation
import ImageIO
import TellomiDiscover
import UIKit

/// Turns a picked image into upload bytes.
/// JPEG, PNG, and WebP keep their compressed pixels. Location metadata is removed first.
/// HEIC/HEIF is written as JPEG without the source properties, so location and the old
/// orientation tag are not copied; ImageIO applies the orientation to the pixels.
enum TellomiDiscoverImageEncode {
    static func prepared(_ data: Data) -> (bytes: Data, width: Int, height: Int)? {
        switch tellomiDiscoverInspectImage(data) {
        case .upload:
            guard let stripped = tellomiDiscoverStripImageLocation(data), case let .upload(_, width, height) = tellomiDiscoverInspectImage(stripped), !tellomiDiscoverImageHasLocation(stripped) else {
                return nil
            }
            return (stripped, width, height)
        case .convertHeic:
            guard let converted = self.jpegStrippingLocation(data) else {
                return nil
            }
            guard let stripped = tellomiDiscoverStripImageLocation(converted.bytes), case let .upload(_, width, height) = tellomiDiscoverInspectImage(stripped), !tellomiDiscoverImageHasLocation(stripped) else {
                return nil
            }
            return (stripped, width, height)
        case .rejected:
            return nil
        }
    }

    private static func jpegStrippingLocation(_ data: Data) -> (bytes: Data, width: Int, height: Int)? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        guard tellomiDiscoverImagePixelsAllowed(width: image.width, height: image.height) else {
            return nil
        }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        let jpeg = encoded as Data
        guard case let .upload(_, width, height) = tellomiDiscoverInspectImage(jpeg) else {
            return nil
        }
        return (jpeg, width, height)
    }
}
