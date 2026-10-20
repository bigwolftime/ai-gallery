import UIKit
import UniformTypeIdentifiers
import LinkPresentation

/// Keep sharing failures explicit and consistent across preparation/presentation.
enum PhotoShareError: LocalizedError {
    case invalidData, emptySelection, missingPhoto, missingPresenter
    case unreadablePhoto(Int), encodingPhoto(Int)

    var errorDescription: String? {
        switch self {
        case .invalidData: return "无法准备分享图片，请重试。"
        case .emptySelection: return "请先选择要分享的照片。"
        case .missingPhoto: return "部分照片已删除或无法访问，请重新选择。"
        case .missingPresenter: return "无法打开分享面板，请返回首页重试。"
        case .unreadablePhoto(let number): return "第 \(number) 张照片无法读取，请检查照片权限或 iCloud 下载后重试。"
        case .encodingPhoto(let number): return "无法准备第 \(number) 张照片，请重试。"
        }
    }
}

/// Share each photo as an image, never a file URL or a nested collection.
/// Keeping JPEG-backed UIImages avoids retaining every full decoded bitmap
/// while preparing a batch of photos for the receiving share extension.
final class PhotoShareItem: NSObject, UIActivityItemSource {
    private let jpegData: Data
    private let image: UIImage

    init(jpegData: Data) throws {
        guard let image = UIImage(data: jpegData) else {
            throw PhotoShareError.invalidData
        }
        self.jpegData = jpegData
        self.image = image
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        image
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        image
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        UTType.jpeg.identifier
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = "照片"
        let provider = NSItemProvider()
        let data = jpegData
        provider.registerDataRepresentation(forTypeIdentifier: UTType.jpeg.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        metadata.imageProvider = provider
        return metadata
    }
}
