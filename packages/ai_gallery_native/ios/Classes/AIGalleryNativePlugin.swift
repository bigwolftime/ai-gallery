import Flutter
import Photos
import UIKit

@MainActor
public final class AIGalleryNativePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private let photoLibrary = PhotoLibraryService()
    private let model = EmbeddingModelService()
    private var progressSink: FlutterEventSink?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let methods = FlutterMethodChannel(name: "ai_gallery/native", binaryMessenger: registrar.messenger())
        let progress = FlutterEventChannel(name: "ai_gallery/progress", binaryMessenger: registrar.messenger())
        let plugin = AIGalleryNativePlugin()
        registrar.addMethodCallDelegate(plugin, channel: methods)
        progress.setStreamHandler(plugin)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        Task { @MainActor in
            do {
                switch call.method {
                case "getAppUpdateInfo":
                    guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                          let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                          let buildNumber = Int(build) else {
                        throw NSError(domain: "AIGallery", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法读取当前应用版本。"])
                    }
                    let receipt = Bundle.main.appStoreReceiptURL
                    let hasReceipt = receipt.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
                    let channel = hasReceipt ? (receipt?.lastPathComponent == "sandboxReceipt" ? "testflight" : "appstore") : "sideload"
                    result(["platform": "ios", "channel": channel, "version": version, "buildNumber": buildNumber])
                case "openUpdateUrl":
                    guard let args = call.arguments as? [String: Any], let value = args["url"] as? String,
                          let url = URL(string: value), url.scheme == "https", url.host != nil else {
                        throw NSError(domain: "AIGallery", code: 1, userInfo: [NSLocalizedDescriptionKey: "更新地址必须使用 HTTPS。"])
                    }
                    guard await UIApplication.shared.open(url) else {
                        throw NSError(domain: "AIGallery", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法打开更新地址，请稍后重试。"])
                    }
                    result(nil)
                case "getModelDirectory":
                    result(try model.modelDirectory().path)
                case "initializeModel":
                    guard let args = call.arguments as? [String: Any],
                          let path = args["modelPath"] as? String, let version = args["indexVersion"] as? String else {
                        throw NSError(domain: "AIGallery", code: 1, userInfo: [NSLocalizedDescriptionKey: "缺少模型路径。"])
                    }
                    try await model.initialize(path: path, version: version)
                    result(nil)
                case "loadPhotos":
                    guard await photoLibrary.requestAccess() else {
                        result(FlutterError(code: "PHOTO_PERMISSION", message: "Photo access is not authorized", details: nil))
                        return
                    }
                    result(photoLibrary.assets().map(photoLibrary.photoMap))
                case "shouldOfferAnalysis":
                    result(!UserDefaults.standard.bool(forKey: "AIGallery.didAskAnalysis.v1"))
                case "dismissAnalysisPrompt":
                    UserDefaults.standard.set(true, forKey: "AIGallery.didAskAnalysis.v1")
                    result(nil)
                case "openSettings":
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        _ = await UIApplication.shared.open(url)
                    }
                    result(nil)
                case "loadThumbnail", "loadImage":
                    let fullSize = call.method == "loadImage"
                    guard let args = call.arguments as? [String: Any],
                          let id = args["id"] as? String, let asset = photoLibrary.asset(id: id),
                          let image = await photoLibrary.image(
                            for: asset, targetSize: CGSize(width: fullSize ? 2400 : 360, height: fullSize ? 2400 : 360),
                            contentMode: fullSize ? .aspectFit : .aspectFill, allowNetworkAccess: fullSize),
                          let data = image.jpegData(compressionQuality: 0.88) else {
                        result(nil)
                        return
                    }
                    result(FlutterStandardTypedData(bytes: data))
                case "hasIndexedPhotos":
                    let ids = (call.arguments as? [String: Any])?["photoIds"] as? [String] ?? []
                    result(model.hasIndexedPhotos(ids))
                case "analyzePhotos":
                    let ids = (call.arguments as? [String: Any])?["photoIds"] as? [String] ?? []
                    let summary = try await model.analyze(ids: ids, photoLibrary: photoLibrary) { [weak self] completed, total in
                        self?.progressSink?( ["completed": completed, "total": total] )
                    }
                    result(summary)
                case "search":
                    let args = call.arguments as? [String: Any]
                    let query = args?["query"] as? String ?? ""
                    let limit = args?["limit"] as? Int ?? 0
                    result(try await model.search(query: query, photoLibrary: photoLibrary, limit: limit))
                case "sharePhotos":
                    let ids = (call.arguments as? [String: Any])?["photoIds"] as? [String] ?? []
                    var seen = Set<String>()
                    let uniqueIDs = ids.filter { seen.insert($0).inserted }
                    guard !uniqueIDs.isEmpty else {
                        throw PhotoShareError.emptySelection
                    }
                    let assets = try uniqueIDs.map { id -> PHAsset in
                        guard let asset = photoLibrary.asset(id: id) else {
                            throw PhotoShareError.missingPhoto
                        }
                        return asset
                    }
                    let items = try await photoLibrary.shareItems(for: assets)
                    try presentShareSheet(items: items)
                    result(nil)
                default:
                    result(FlutterMethodNotImplemented)
                }
            } catch {
                result(FlutterError(code: "NATIVE_ERROR", message: error.localizedDescription, details: nil))
            }
        }
    }

    private func presentShareSheet(items: [PhotoShareItem]) throws {
        guard !items.isEmpty, let root = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).filter({ $0.activationState == .foregroundActive }).flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
            throw PhotoShareError.missingPresenter
        }
        var presenter = root
        while let presented = presenter.presentedViewController { presenter = presented }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad requires a popover anchor even when invoked from a Flutter route.
        sheet.popoverPresentationController?.sourceView = presenter.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY - 20, width: 1, height: 1)
        presenter.present(sheet, animated: true)
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        progressSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        progressSink = nil
        return nil
    }
}
