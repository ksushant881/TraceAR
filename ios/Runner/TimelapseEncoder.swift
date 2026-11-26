import AVFoundation
import Foundation
import UIKit

enum TimelapseEncoder {
    static func encode(
        frameDir: String,
        outPath: String,
        fps: Int,
        onProgress: @escaping (Double) -> Void,
        onSuccess: @escaping (String) -> Void,
        onError: @escaping (String, String) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let resultPath = try encodeSync(
                    frameDir: frameDir,
                    outPath: outPath,
                    fps: fps
                ) { progress in
                    DispatchQueue.main.async {
                        onProgress(progress)
                    }
                }
                DispatchQueue.main.async {
                    onSuccess(resultPath)
                }
            } catch {
                DispatchQueue.main.async {
                    onError("ENCODE_ERROR", error.localizedDescription)
                }
            }
        }
    }

    private static func encodeSync(
        frameDir: String,
        outPath: String,
        fps: Int,
        onProgress: (Double) -> Void
    ) throws -> String {
        let fm = FileManager.default
        let dirUrl = URL(fileURLWithPath: frameDir)
        let files = try fm.contentsOfDirectory(at: dirUrl, includingPropertiesForKeys: nil)
            .filter {
                let ext = $0.pathExtension.lowercased()
                return ext == "jpg" || ext == "jpeg"
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard let firstUrl = files.first,
              let firstImage = UIImage(contentsOfFile: firstUrl.path) else {
            throw NSError(
                domain: "TimelapseEncoder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No JPEG frames found in \(frameDir)"]
            )
        }

        let rawW = firstImage.size.width * firstImage.scale
        let rawH = firstImage.size.height * firstImage.scale
        let longSide = max(rawW, rawH)
        let scale = longSide > 1920 ? 1920.0 / longSide : 1.0
        var width = Int(rawW * scale)
        var height = Int(rawH * scale)
        width = max(2, width & ~1)
        height = max(2, height & ~1)

        let outUrl = URL(fileURLWithPath: outPath)
        try? fm.removeItem(at: outUrl)
        try fm.createDirectory(
            at: outUrl.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let writer = try AVAssetWriter(outputURL: outUrl, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attrs
        )

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let safeFps = Int32(max(1, min(fps, 60)))
        let total = Double(files.count)

        for (index, fileUrl) in files.enumerated() {
            autoreleasepool {
                while !input.isReadyForMoreMediaData {
                    Thread.sleep(forTimeInterval: 0.01)
                }
                if let image = UIImage(contentsOfFile: fileUrl.path),
                   let buffer = pixelBuffer(from: image, width: width, height: height) {
                    let time = CMTime(value: CMTimeValue(index), timescale: safeFps)
                    adaptor.append(buffer, withPresentationTime: time)
                }
            }
            onProgress(Double(index + 1) / total)
        }

        input.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()

        if writer.status == .failed {
            throw writer.error ?? NSError(
                domain: "TimelapseEncoder",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "AVAssetWriter failed"]
            )
        }

        return outPath
    }

    private static func pixelBuffer(from image: UIImage, width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            options as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            return nil
        }

        // Camera JPEGs carry an EXIF orientation; `cgImage` is the raw,
        // unrotated sensor image. `UIImage.draw(in:)` applies the
        // orientation, so draw through UIKit (top-left origin) instead.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()
        return buffer
    }
}
