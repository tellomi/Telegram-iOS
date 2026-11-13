import ImageIO
import UIKit
import XCTest
import TellomiDiscover
import TellomiFeedScreen

final class TellomiFeedProofTests: XCTestCase {
    func testFeedModuleIsTheIOSBuild() {
        XCTAssertTrue(true)
    }

    /// ImageIO on the simulator, not a byte-prefix check. A one-pixel bitmap is
    /// written as HEIC when this SDK can, then the app path turns it into JPEG
    /// with no location metadata.
    func testImageIOHeicBecomesJpegWithoutLocation() throws {
        let width = 8
        let height = 8
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            XCTFail("ImageIO context was not created")
            return
        }
        context.setFillColor(UIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            XCTFail("ImageIO produced no image")
            return
        }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, "public.heic" as CFString, 1, nil) else {
            throw XCTSkip("this SDK has no HEIC encoder")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            XCTFail("ImageIO did not write HEIC")
            return
        }
        let heic = encoded as Data
        XCTAssertEqual(tellomiDiscoverInspectImage(heic), .convertHeic)
        guard let prepared = TellomiDiscoverImageEncode.prepared(heic) else {
            XCTFail("HEIC was not converted")
            return
        }
        XCTAssertEqual(tellomiDiscoverInspectImage(prepared.bytes), .upload(kind: "jpeg", width: width, height: height))
        XCTAssertFalse(tellomiDiscoverImageHasLocation(prepared.bytes))
        XCTAssertEqual([UInt8](prepared.bytes.prefix(2)), [0xFF, 0xD8])
    }
}
