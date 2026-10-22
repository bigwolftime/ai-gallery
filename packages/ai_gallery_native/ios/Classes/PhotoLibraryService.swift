import Photos
import UIKit

@MainActor
final class PhotoLibraryService {
    private let imageManager = PHCachingImageManager()
    private static let shareSize = CGSize(width: 2400, height: 2400)
    private static let shareQuality: CGFloat = 0.92

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

    /// `onProgress` fires only while Photos downloads the original from iCloud.
    func image(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode, allowNetworkAccess: Bool,
               onProgress: (@MainActor @Sendable (Double) -> Void)? = nil) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = allowNetworkAccess
            if let onProgress {
                // Photos calls this on a background queue.
                options.progressHandler = { progress, _, _, _ in
                    Task { @MainActor in onProgress(progress) }
                }
            }
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

    func shareItems(for assets: [PHAsset]) async throws -> [PhotoShareItem] {
        var items: [PhotoShareItem] = []
        items.reserveCapacity(assets.count)
        for (index, asset) in assets.enumerated() {
            guard let image = await image(for: asset, targetSize: Self.shareSize, contentMode: .aspectFit, allowNetworkAccess: true) else {
                // Never silently turn a multiple-photo selection into one item.
                throw PhotoShareError.unreadablePhoto(index + 1)
            }
            let item = try autoreleasepool { () throws -> PhotoShareItem in
                guard let data = image.jpegData(compressionQuality: Self.shareQuality) else {
                    throw PhotoShareError.encodingPhoto(index + 1)
                }
                return try PhotoShareItem(jpegData: data)
            }
            items.append(item)
        }
        return items
    }
}
