import AVFoundation
import UIKit

/// 2 秒クリップを連結して「思い出ビデオ」を書き出す（オンデバイス合成。AGENTS.md の決定事項）。
///
/// - 縦長 1080x1920 にアスペクトフィルで揃える（向きの違うクリップが混ざっても崩れない）
/// - 音源は居住者が自分で選んだ MP3（等）のみ。指定があればクリップの音は使わず音源を流し、最後をフェードアウトする。
///   YouTube などからの音声抽出は行わない
enum MemoryVideoComposer {
    static let renderSize = CGSize(width: 1080, height: 1920)

    static func compose(clips: [URL], music: URL?, to output: URL) async throws {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ClipError.exportFailed("video track")
        }
        let clipAudioTrack = music == nil
            ? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            : nil

        var cursor = CMTime.zero
        var instructions: [AVMutableVideoCompositionInstruction] = []

        for url in clips {
            let asset = AVURLAsset(url: url)
            guard let source = try await asset.loadTracks(withMediaType: .video).first else { continue }
            let duration = CMTimeMinimum(
                try await asset.load(.duration),
                CMTime(seconds: ClipProcessing.clipSeconds, preferredTimescale: 600)
            )
            let range = CMTimeRange(start: .zero, duration: duration)
            try videoTrack.insertTimeRange(range, of: source, at: cursor)
            if let clipAudioTrack, let audio = try await asset.loadTracks(withMediaType: .audio).first {
                try? clipAudioTrack.insertTimeRange(range, of: audio, at: cursor)
            }

            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            layer.setTransform(try await fillTransform(for: source), at: cursor)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: cursor, duration: duration)
            instruction.layerInstructions = [layer]
            instructions.append(instruction)

            cursor = cursor + duration
        }
        guard cursor > .zero else { throw ClipError.noVideoTrack }
        // 音の無いクリップだけだと空の音声トラックが残り、書き出しが失敗するので外す
        if let clipAudioTrack, clipAudioTrack.segments.isEmpty {
            composition.removeTrack(clipAudioTrack)
        }

        var audioMix: AVMutableAudioMix?
        if let music {
            audioMix = try await addMusic(music, to: composition, length: cursor)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = instructions

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ClipError.exportFailed("export session")
        }
        try? FileManager.default.removeItem(at: output)
        export.outputURL = output
        export.outputFileType = .mp4
        export.videoComposition = videoComposition
        export.audioMix = audioMix
        await export.export()
        guard export.status == .completed else {
            throw ClipError.exportFailed(export.error?.localizedDescription ?? "unknown")
        }
    }

    /// 撮影時の向き（preferredTransform）を反映したうえで、renderSize をはみ出しなく埋める変換
    private static func fillTransform(for track: AVAssetTrack) async throws -> CGAffineTransform {
        let natural = try await track.load(.naturalSize)
        let preferred = try await track.load(.preferredTransform)
        let oriented = CGRect(origin: .zero, size: natural).applying(preferred)
        let size = CGSize(width: abs(oriented.width), height: abs(oriented.height))
        let scale = max(renderSize.width / size.width, renderSize.height / size.height)

        return preferred
            .concatenating(CGAffineTransform(translationX: -oriented.minX, y: -oriented.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(
                translationX: (renderSize.width - size.width * scale) / 2,
                y: (renderSize.height - size.height * scale) / 2
            ))
    }

    /// 音源を動画の長さまで敷き詰め（短ければループ）、最後の 1 秒でフェードアウトする
    private static func addMusic(_ url: URL, to composition: AVMutableComposition, length: CMTime) async throws -> AVMutableAudioMix? {
        let asset = AVURLAsset(url: url)
        guard let source = try await asset.loadTracks(withMediaType: .audio).first,
              let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }
        let musicLength = try await asset.load(.duration)
        guard musicLength > .zero else { return nil }

        var cursor = CMTime.zero
        while cursor < length {
            let chunk = CMTimeMinimum(musicLength, length - cursor)
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: chunk), of: source, at: cursor)
            cursor = cursor + chunk
        }

        let params = AVMutableAudioMixInputParameters(track: track)
        let fade = CMTimeMinimum(CMTime(seconds: 1, preferredTimescale: 600), length)
        params.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: CMTimeRange(start: length - fade, duration: fade))
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        return mix
    }
}
