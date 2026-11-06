import Foundation
import ImageIO
import TellomiDiscover
import UIKit

/// Turns a picked image into upload bytes.
/// JPEG, PNG, and WebP that already fit the caps are uploaded unchanged.
/// HEIC/HEIF is written as JPEG without the source properties, so the location metadata is not copied.
enum TellomiDiscoverImageEncode {
    static func prepared(_ data: Data) -> (bytes: Data, width: Int, height: Int)? {
        switch tellomiDiscoverInspectImage(data) {
        case let .upload(_, width, height):
            return (data, width, height)
        case .convertHeic:
            return self.jpegStrippingLocation(data)
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
