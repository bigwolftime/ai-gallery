import UIKit
import UniformTypeIdentifiers

/// Standalone UIKit contract checks; compile with PhotoShareItem.swift using
/// Mac Catalyst so the device-only LiteRT-LM framework is not needed by tests.
@main
struct PhotoShareItemChecks {
    @MainActor
    static func main() throws {
        let context = CGContext(data: nil, width: 8, height: 8,
                                bitsPerComponent: 8, bytesPerRow: 32,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(UIColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let data = UIImage(cgImage: context.makeImage()!).jpegData(compressionQuality: 0.92)!
        let items = try [data, data, data].map { try PhotoShareItem(jpegData: $0) }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        precondition(items.count == 3, "Every selected image must remain an individual item")
        for item in items {
            precondition(item.activityViewControllerPlaceholderItem(sheet) is UIImage)
            let payload = item.activityViewController(sheet,
                itemForActivityType: UIActivity.ActivityType("com.tencent.xin.share"))
            precondition(payload is UIImage && !(payload is URL), "Wechat must receive images rather than file URLs")
            precondition(item.activityViewController(sheet, dataTypeIdentifierForActivityType: nil) == UTType.jpeg.identifier)
            let metadata = item.activityViewControllerLinkMetadata(sheet)!
            precondition(metadata.url == nil && metadata.originalURL == nil)
            let provider = metadata.imageProvider!
            precondition(provider.hasItemConformingToTypeIdentifier(UTType.image.identifier))
            let semaphore = DispatchSemaphore(value: 0)
            provider.loadDataRepresentation(forTypeIdentifier: UTType.jpeg.identifier) { bytes, error in
                precondition(error == nil && bytes == data)
                precondition(UIImage(data: bytes!) != nil)
                semaphore.signal()
            }
            precondition(semaphore.wait(timeout: .now() + 5) == .success,
                         "Image preview provider must return valid JPEG data")
        }
        do {
            _ = try PhotoShareItem(jpegData: Data("invalid image".utf8))
            preconditionFailure("Invalid image data must fail explicitly")
        } catch {}
        print("Native sharing checks passed: 3 image items, JPEG type, decodable preview, invalid image rejection.")
    }
}
