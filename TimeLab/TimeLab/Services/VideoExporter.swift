import AVFoundation
import AppKit
import Foundation
import VideoToolbox

final class VideoExporter {

    enum ExportError: LocalizedError {
        case noFrames
        case cannotCreateWriter(Error)
        case cannotLoadImage(String)
        case writerFailed(String)

        var errorDescription: String? {
            switch self {
            case .noFrames: return "No frames found to export."
            case .cannotCreateWriter(let e): return "Cannot create writer: \(e.localizedDescription)"
            case .cannotLoadImage(let p): return "Cannot load image: \(p)"
            case .writerFailed(let s): return "Writer failed: \(s)"
            }
        }
    }

    static func exportVideo(
        framesDirectory: URL,
        outputURL: URL,
        fps: Int,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {

        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(at: framesDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !files.isEmpty else { throw ExportError.noFrames }

        guard let firstImage = NSImage(contentsOf: files[0]),
              let firstRep = firstImage.representations.first else {
            throw ExportError.cannotLoadImage(files[0].lastPathComponent)
        }

        let width = firstRep.pixelsWide
        let height = firstRep.pixelsHigh

        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw ExportError.cannotCreateWriter(error)
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 4,
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel,
            ],
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )

        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        let totalFrames = files.count

        for (index, fileURL) in files.enumerated() {
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)
            }

            guard let pixelBuffer = pixelBuffer(from: fileURL, width: width, height: height) else {
                throw ExportError.cannotLoadImage(fileURL.lastPathComponent)
            }

            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(index))
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)

            let currentProgress = Double(index + 1) / Double(totalFrames)
            await MainActor.run { progress(currentProgress) }
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw ExportError.writerFailed(writer.error?.localizedDescription ?? "Unknown error")
        }

        return outputURL
    }

    private static func pixelBuffer(from imageURL: URL, width: Int, height: Int) -> CVPixelBuffer? {
        guard let image = NSImage(contentsOf: imageURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32ARGB,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

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
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
