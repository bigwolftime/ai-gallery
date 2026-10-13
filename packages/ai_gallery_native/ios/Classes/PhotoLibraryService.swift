import Photos
import UIKit

@MainActor
final class PhotoLibraryService {
    private let imageManager = PHCachingImageManager()

    func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    func assets() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    func photoMap(_ asset: PHAsset) -> [String: Any] {
        var map: [String: Any] = [
            "id": asset.localIdentifier,
            "uri": "ph://\(asset.localIdentifier)",
            "width": asset.pixelWidth,
            "height": asset.pixelHeight,
        ]
        if let date = asset.creationDate { map["createdAt"] = ISO8601DateFormatter().string(from: date) }
        return map
    }

    func imageData(for asset: PHAsset, targetSize: CGSize = CGSize(width: 1024, height: 1024)) async -> Data? {
        guard let image = await image(for: asset, targetSize: targetSize, contentMode: .aspectFit, allowNetworkAccess: true) else { return nil }
        return image.jpegData(compressionQuality: 0.88)
    }

    func image(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode, allowNetworkAccess: Bool) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = allowNetworkAccess
            var resumed = false
            imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: contentMode, options: options) { image, info in
                guard !resumed else { return }
                if let image {
                    resumed = true
                    continuation.resume(returning: image)
                } else if info?[PHImageErrorKey] != nil || info?[PHImageCancelledKey] as? Bool == true || info?[PHImageResultIsDegradedKey] as? Bool != true {
                    resumed = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // Fetch individual thumbnails by identifier instead of scanning the whole library.
    func asset(id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    func assetMapByID() -> [String: PHAsset] {
        Dictionary(uniqueKeysWithValues: assets().map { ($0.localIdentifier, $0) })
    }

    func shareURLs(for assets: [PHAsset]) async -> [URL] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIGalleryShare", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = []
        for (index, asset) in assets.enumerated() {
            guard let image = await image(for: asset, targetSize: CGSize(width: 2400, height: 2400), contentMode: .aspectFit, allowNetworkAccess: true), let data = image.jpegData(compressionQuality: 0.92) else { continue }
            let url = directory.appendingPathComponent("AI-Gallery-\(index + 1).jpg")
            try? data.write(to: url, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) { urls.append(url) }
        }
        return urls
    }
}
