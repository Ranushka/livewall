import AVFoundation
import CoreMedia
import Photos
import UniformTypeIdentifiers
import UIKit

/// How the video sits in the Lock Screen frame. `pan` is in render pixels.
struct Framing: Equatable {
    var zoom: CGFloat = 1
    var pan: CGSize = .zero
}

enum ExportError: LocalizedError {
    case noVideoTrack, exportFailed(String), noPhotoAccess
    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "This file has no video."
        case .exportFailed(let m): return "Could not make the Live Photo: \(m)"
        case .noPhotoAccess: return "LiveWall needs permission to add photos. Allow it in Settings."
        }
    }
}

/// Crop + trim a video, then write a Live Photo pair: a JPEG and a MOV that share a content identifier.
enum LivePhotoExporter {
    static let renderSize = CGSize(width: 1080, height: 2340)
    static let clipSeconds = 3.0

    struct Output { let photo: URL; let video: URL }

    static func export(source: URL, start: Double, framing: Framing) async throws -> Output {
        let id = UUID().uuidString
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(id)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let cropped = dir.appendingPathComponent("cropped.mov")
        let finalVideo = dir.appendingPathComponent("\(id).mov")
        let photo = dir.appendingPathComponent("\(id).jpg")

        let length = try await crop(source: source, start: start, framing: framing, to: cropped)
        let mid = length / 2
        try await writeLiveVideo(from: cropped, to: finalVideo, id: id, stillTime: mid)
        try await writeStill(from: cropped, at: mid, to: photo, id: id)
        return Output(photo: photo, video: finalVideo)
    }

    // MARK: Crop and trim

    private static func crop(source: URL, start: Double, framing: Framing, to out: URL) async throws -> Double {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw ExportError.noVideoTrack }
        let (natural, pref, duration) = try await (track.load(.naturalSize), track.load(.preferredTransform), asset.load(.duration))

        let oriented = natural.applying(pref)
        let w = abs(oriented.width), h = abs(oriented.height)
        let r = renderSize
        let scale = max(r.width / w, r.height / h) * framing.zoom
        let transform = pref
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: (r.width - w * scale) / 2 + framing.pan.width,
                                             y: (r.height - h * scale) / 2 + framing.pan.height))

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(transform, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layer]
        let composition = AVMutableVideoComposition()
        composition.renderSize = r
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        composition.instructions = [instruction]

        let total = duration.seconds
        let clipStart = min(max(0, start), max(0, total - 0.1))
        let clipLength = min(clipSeconds, total - clipStart)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.exportFailed("export session unavailable")
        }
        session.outputURL = out
        session.outputFileType = .mov
        session.videoComposition = composition
        session.timeRange = CMTimeRange(start: CMTime(seconds: clipStart, preferredTimescale: 600),
                                        duration: CMTime(seconds: clipLength, preferredTimescale: 600))
        await session.export()
        guard session.status == .completed else {
            throw ExportError.exportFailed(session.error?.localizedDescription ?? "unknown error")
        }
        return clipLength
    }

    // MARK: Live Photo video (content identifier + still-image-time)

    private static func writeLiveVideo(from src: URL, to dst: URL, id: String, stillTime: Double) async throws {
        let asset = AVURLAsset(url: src)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw ExportError.noVideoTrack }
        let formats = try await track.load(.formatDescriptions)
        let transform = try await track.load(.preferredTransform)

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: dst, fileType: .mov)
        let idItem = AVMutableMetadataItem()
        idItem.key = AVMetadataKey.quickTimeMetadataKeyContentIdentifier as NSString
        idItem.keySpace = .quickTimeMetadata
        idItem.value = id as NSString
        idItem.dataType = "com.apple.metadata.datatype.UTF-8"
        writer.metadata = [idItem]

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formats.first)
        videoInput.transform = transform
        writer.add(videoInput)

        let spec: [String: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: "com.apple.metadata.datatype.int8",
        ]
        var metaFormat: CMFormatDescription?
        CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault, metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [spec] as CFArray, formatDescriptionOut: &metaFormat)
        let metaInput = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: metaFormat)
        let adaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metaInput)
        writer.add(metaInput)

        guard writer.startWriting() else { throw ExportError.exportFailed(writer.error?.localizedDescription ?? "writer") }
        writer.startSession(atSourceTime: .zero)
        reader.startReading()

        let still = AVMutableMetadataItem()
        still.key = "com.apple.quicktime.still-image-time" as NSString
        still.keySpace = .quickTimeMetadata
        still.value = 0 as NSNumber
        still.dataType = "com.apple.metadata.datatype.int8"
        adaptor.append(AVTimedMetadataGroup(
            items: [still],
            timeRange: CMTimeRange(start: CMTime(seconds: stillTime, preferredTimescale: 600),
                                   duration: CMTime(value: 1, timescale: 30))))
        metaInput.markAsFinished()

        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let queue = DispatchQueue(label: "livewall.writer")
            videoInput.requestMediaDataWhenReady(on: queue) {
                while videoInput.isReadyForMoreMediaData {
                    if let sample = readerOutput.copyNextSampleBuffer() {
                        videoInput.append(sample)
                    } else {
                        videoInput.markAsFinished()
                        done.resume()
                        return
                    }
                }
            }
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw ExportError.exportFailed(writer.error?.localizedDescription ?? "writer failed")
        }
    }

    // MARK: Live Photo still (JPEG with the same identifier)

    private static func writeStill(from video: URL, at seconds: Double, to out: URL, id: String) async throws {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ExportError.exportFailed("could not create JPEG")
        }
        let props: [CFString: Any] = [
            kCGImagePropertyMakerAppleDictionary: ["17": id],
            kCGImageDestinationLossyCompressionQuality: 0.95,
        ]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ExportError.exportFailed("could not write JPEG") }
    }

    // MARK: Save

    static func saveToPhotos(_ output: Output) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw ExportError.noPhotoAccess }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: output.photo, options: nil)
            request.addResource(with: .pairedVideo, fileURL: output.video, options: nil)
        }
        try? FileManager.default.removeItem(at: output.video.deletingLastPathComponent())
    }
}
