import AVFoundation
import UIKit

/// モックモード用のサンプル 2 秒クリップを生成する。
/// カメラの無いシミュレータでも日記・思い出ビデオを試せるように、色が流れる背景に文字を描いた動画を作る。
enum SampleClipGenerator {
    private static let size = CGSize(width: 720, height: 1280)
    private static let fps: Int32 = 30

    static func generate(to url: URL, title: String, subtitle: String, hue: CGFloat) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        guard writer.startWriting() else { throw ClipError.exportFailed(writer.error?.localizedDescription ?? "writer") }
        writer.startSession(atSourceTime: .zero)

        let frames = Int(ClipProcessing.clipSeconds * Double(fps))
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { break }
            draw(into: buffer, progress: CGFloat(frame) / CGFloat(frames), title: title, subtitle: subtitle, hue: hue)
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw ClipError.exportFailed(writer.error?.localizedDescription ?? "writer")
        }
    }

    private static func draw(into buffer: CVPixelBuffer, progress: CGFloat, title: String, subtitle: String, hue: CGFloat) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return }

        // UIKit と同じ左上原点にする
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }

        let top = UIColor(hue: (hue + progress * 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 0.95, alpha: 1)
        let bottom = UIColor(hue: (hue + 0.12 + progress * 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.7, alpha: 1)
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width * progress, y: size.height), options: [])
        }

        // ゆっくり動く円で「動画らしさ」を出す
        UIColor.white.withAlphaComponent(0.18).setFill()
        let radius: CGFloat = 220
        UIBezierPath(ovalIn: CGRect(x: -radius + size.width * progress * 1.2, y: size.height * 0.62, width: radius * 2, height: radius * 2)).fill()

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 64, weight: .heavy),
            .foregroundColor: UIColor.white,
        ]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 36, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.85),
        ]
        let titleSize = (title as NSString).size(withAttributes: titleAttrs)
        (title as NSString).draw(at: CGPoint(x: (size.width - titleSize.width) / 2, y: size.height * 0.4), withAttributes: titleAttrs)
        let subSize = (subtitle as NSString).size(withAttributes: subtitleAttrs)
        (subtitle as NSString).draw(at: CGPoint(x: (size.width - subSize.width) / 2, y: size.height * 0.4 + 90), withAttributes: subtitleAttrs)
    }
}
