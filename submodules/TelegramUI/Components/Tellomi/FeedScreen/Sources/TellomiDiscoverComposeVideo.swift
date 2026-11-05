import AVFoundation
import Foundation
import PhotosUI
import SwiftSignalKit
import TellomiDiscover
import UIKit

/// A picked video copied into the temp directory. The bytes stay on device.
/// Nothing here uploads, transcodes, or trims.
enum TellomiDiscoverLocalVideo {
    private static let filePrefix = "tellomi-discover-"

    static func milliseconds(at url: URL, completion: @escaping (Int64) -> Void) {
        let precise = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        precise.loadValuesAsynchronously(forKeys: ["duration"]) {
            let exact = Self.milliseconds(of: precise)
            if exact > 0 {
                Queue.mainQueue().async {
                    completion(exact)
                }
                return
            }
            let fallback = AVURLAsset(url: url)
            fallback.loadValuesAsynchronously(forKeys: ["duration"]) {
                let value = Self.milliseconds(of: fallback)
                Queue.mainQueue().async {
                    completion(value)
                }
            }
        }
    }

    static func preview(at url: URL, completion: @escaping (UIImage?) -> Void) {
        let asset = AVURLAsset(url: url)
        asset.loadValuesAsynchronously(forKeys: ["duration"]) {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 600, height: 600)
            let image: UIImage?
            if let cgImage = try? generator.copyCGImage(at: CMTime(seconds: 0, preferredTimescale: 600), actualTime: nil) {
                image = UIImage(cgImage: cgImage)
            } else {
                image = nil
            }
            Queue.mainQueue().async {
                completion(image)
            }
        }
    }

    static func discard(_ url: URL?) {
        guard let url, url.lastPathComponent.hasPrefix(self.filePrefix) else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    fileprivate static func copyMovie(from source: URL) -> URL? {
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(self.filePrefix + UUID().uuidString + "." + ext)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private static func milliseconds(of asset: AVAsset) -> Int64 {
        var error: NSError?
        let status = asset.statusOfValue(forKey: "duration", error: &error)
        if status != .loaded || error != nil {
            return 0
        }
        let time = asset.duration
        return TellomiDiscoverVideo.milliseconds(timeValue: time.value, timescale: time.timescale, numeric: time.isNumeric)
    }
}

/// System video picker. The original file is copied locally. The picker is not
/// asked to limit duration, so a long clip arrives whole and the cap can reject
/// it instead of trimming it.
@available(iOS 14.0, *)
final class TellomiDiscoverVideoPicker: NSObject, PHPickerViewControllerDelegate {
    var onBegin: (() -> Void)?
    var onPick: ((URL) -> Void)?
    var onUnreadable: (() -> Void)?

    func present(from controller: UIViewController) {
        var configuration = PHPickerConfiguration()
        configuration.filter = .videos
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        controller.present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else {
            return
        }
        self.onBegin?()
        let movie = "public.movie"
        let type: String
        if provider.hasItemConformingToTypeIdentifier(movie) {
            type = movie
        } else if let registered = provider.registeredTypeIdentifiers.first(where: { identifier in
            let name = identifier.lowercased()
            return name.contains("video") || name.contains("movie") || name.contains("mpeg")
        }) {
            type = registered
        } else {
            self.onUnreadable?()
            return
        }
        provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
            let copied = url.flatMap { TellomiDiscoverLocalVideo.copyMovie(from: $0) }
            Queue.mainQueue().async {
                if let copied {
                    self.onPick?(copied)
                } else {
                    self.onUnreadable?()
                }
            }
        }
    }
}
