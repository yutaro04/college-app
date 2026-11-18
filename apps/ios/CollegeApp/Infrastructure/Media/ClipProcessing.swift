import AVFoundation
import UIKit

enum ClipError: LocalizedError {
    case noVideoTrack
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "動画を読み込めませんでした"
        case .exportFailed(let message): return "動画の書き出しに失敗しました（\(message)）"
        }
    }
}

/// クリップの切り出し・サムネイル
enum ClipProcessing {
    /// 1 本あたりの長さ（setlog の 1 秒より少し長い 2 秒）
    static let clipSeconds = 2.0

    /// 撮影・選択した動画の先頭 2 秒を mp4 で書き出す。既存ファイルは上書きする
    static func trimToClip(source: URL, destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard try await !asset.loadTracks(withMediaType: .video).isEmpty else { throw ClipError.noVideoTrack }
        let duration = try await asset.load(.duration)
        let length = CMTimeMinimum(duration, CMTime(seconds: clipSeconds, preferredTimescale: 600))

        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ClipError.exportFailed("export session")
        }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        export.outputURL = temp
        export.outputFileType = .mp4
        export.timeRange = CMTimeRange(start: .zero, duration: length)
        await export.export()
        guard export.status == .completed else {
            throw ClipError.exportFailed(export.error?.localizedDescription ?? "unknown")
        }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
    }

    /// 先頭フレームのサムネイル（向きを反映する）
    static func thumbnail(for url: URL, maxSize: CGFloat = 300) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSize, height: maxSize)
        guard let (image, _) = try? await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)) else {
            return nil
        }
        return UIImage(cgImage: image)
    }
}

/// サムネイルのメモリキャッシュ
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private var cache: [URL: UIImage] = [:]

    func image(for url: URL) async -> UIImage? {
        if let cached = cache[url] { return cached }
        let image = await ClipProcessing.thumbnail(for: url)
        cache[url] = image
        return image
    }

    func invalidate(_ url: URL) {
        cache[url] = nil
    }
}
