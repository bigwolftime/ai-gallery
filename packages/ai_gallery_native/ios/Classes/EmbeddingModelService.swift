import Foundation
import Photos

@MainActor
final class EmbeddingModelService {
    private let index = EmbeddingIndexService()
    private var engine: EmbeddingEngine?
    private var analyzing = false
    private let dimensions = 256
    private let visionTokens = 70

    private var loadedPath: String?

    func modelDirectory() throws -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var directory = root.appendingPathComponent("AIGallery/models", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try directory.setResourceValues(resources)
        return directory
    }

    func initialize(path: String, version: String) async throws {
        if engine != nil && loadedPath == path && index.modelVersion == version { return }
        let modelURL = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let directory = try modelDirectory().standardizedFileURL.resolvingSymlinksInPath()
        guard modelURL.deletingLastPathComponent() == directory,
              FileManager.default.fileExists(atPath: modelURL.path), !version.isEmpty else {
            throw failure("下载模型不存在或路径不正确。")
        }
        if let oldEngine = engine { await oldEngine.close(); engine = nil }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("LiteRTLM", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let config = EmbeddingEngineConfig(modelPath: modelURL.path, backend: .gpu, visionBackend: .gpu, cacheDir: cache.path, visionTokensPerImage: visionTokens)
        let newEngine = EmbeddingEngine(config: config)
        try await newEngine.initialize()
        engine = newEngine
        loadedPath = path
        index.modelVersion = version
    }

    func hasIndexedPhotos(_ ids: [String]) -> Bool { index.hasAnyCurrentRecord(ids) }

    func analyze(ids: [String], photoLibrary: PhotoLibraryService, progress: @escaping (Int, Int) -> Void) async throws -> [String: Int] {
        guard let engine else { throw failure("模型未初始化。") }
        guard !analyzing else { throw failure("正在分析照片，请稍候。") }
        analyzing = true
        defer { analyzing = false }
        let assets = photoLibrary.assetMapByID()
        let pending = index.pendingIDs(ids).filter { assets[$0] != nil }
        var completed = 0
        var succeeded = 0
        progress(0, pending.count)
        for id in pending {
            do {
                guard let asset = assets[id], let data = await photoLibrary.imageData(for: asset) else {
                    completed += 1; progress(completed, pending.count); continue
                }
                let response = try await engine.computeEmbedding(contents: [.imageData(data)], options: EmbeddingOptions(normalize: true, outputSize: dimensions, visionTokensPerImage: visionTokens))
                index.upsert(id: id, vector: try normalized(response.embedding))
                succeeded += 1
            } catch {
                // Failed/cloud-unavailable photos remain pending for the next manual run.
            }
            completed += 1
            progress(completed, pending.count)
            if completed % 12 == 0 { try index.save() }
        }
        try index.save()
        return ["processed": completed, "succeeded": succeeded, "failed": completed - succeeded]
    }

    func search(query: String, photoLibrary: PhotoLibraryService, limit: Int) async throws -> [[String: Any]] {
        guard let engine else { throw failure("模型未初始化。") }
        let response = try await engine.computeEmbedding(contents: [.text("task: search query | text: \(query.trimmingCharacters(in: .whitespacesAndNewlines))")], options: EmbeddingOptions(normalize: true, outputSize: dimensions))
        return index.rank(query: try normalized(response.embedding), assets: photoLibrary.assets(), limit: limit, photoLibrary: photoLibrary)
    }

    private func normalized(_ values: [Float]) throws -> [Float] {
        guard values.count >= dimensions else { throw failure("模型返回的向量维度不正确。") }
        let vector = Array(values.prefix(dimensions))
        guard vector.allSatisfy(\.isFinite) else { throw failure("模型返回了无效向量。") }
        let norm = sqrt(vector.reduce(Float.zero) { $0 + $1 * $1 })
        guard norm.isFinite, norm > 0 else { throw failure("模型返回了空向量。") }
        return vector.map { $0 / norm }
    }
    private func failure(_ message: String) -> NSError {
        NSError(domain: "AIGalleryNative", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
