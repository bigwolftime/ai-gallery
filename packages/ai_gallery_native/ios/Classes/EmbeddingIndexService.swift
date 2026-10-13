import Foundation
import Photos

struct NativeEmbeddingRecord: Codable {
    let assetIdentifier: String
    let vector: [Float]
    let modelVersion: String
    let indexedAt: Date
}

@MainActor
final class EmbeddingIndexService {
    var modelVersion = "embeddinggemma-2-256-v1"
    private(set) var records: [String: NativeEmbeddingRecord] = [:]
    private let fileURL: URL

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = root.appendingPathComponent("AIGallery", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("photo-embeddings.json")
        if let data = try? Data(contentsOf: fileURL), let decoded = try? JSONDecoder().decode([NativeEmbeddingRecord].self, from: data) {
            records = Dictionary(uniqueKeysWithValues: decoded.map { ($0.assetIdentifier, $0) })
        }
    }

    func save() throws {
        let data = try JSONEncoder().encode(Array(records.values))
        try data.write(to: fileURL, options: .atomic)
    }

    func hasAnyCurrentRecord(_ ids: [String]) -> Bool {
        ids.contains { records[$0]?.modelVersion == modelVersion }
    }

    func pendingIDs(_ ids: [String]) -> [String] {
        ids.filter { records[$0]?.modelVersion != modelVersion }
    }

    func upsert(id: String, vector: [Float]) {
        records[id] = NativeEmbeddingRecord(assetIdentifier: id, vector: vector, modelVersion: modelVersion, indexedAt: Date())
    }

    func rank(query: [Float], assets: [PHAsset], limit: Int = 0, photoLibrary: PhotoLibraryService) -> [[String: Any]] {
        let ranked = assets.compactMap { asset -> (PHAsset, Float)? in
            guard let record = records[asset.localIdentifier], record.modelVersion == modelVersion else { return nil }
            return (asset, cosine(query, record.vector))
        }.sorted { $0.1 > $1.1 }
        let limited = limit > 0 ? ranked.prefix(limit) : ranked[...]
        return limited.map { ["photo": photoLibrary.photoMap($0.0), "score": $0.1] }
    }

    private func cosine(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return -1 }
        var dot: Float = 0; var left: Float = 0; var right: Float = 0
        for index in lhs.indices { dot += lhs[index] * rhs[index]; left += lhs[index] * lhs[index]; right += rhs[index] * rhs[index] }
        guard left > 0, right > 0 else { return -1 }
        return dot / (sqrt(left) * sqrt(right))
    }
}
