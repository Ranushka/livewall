import AVFoundation
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// A video picked in the Photos picker, copied to a temp file we own.
struct PickedVideo: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            PickedVideo(url: try VideoImport.copyToTemp(received.file))
        }
    }
}

enum VideoImportError: LocalizedError {
    case notVideo, insecure, failed(String)
    var errorDescription: String? {
        switch self {
        case .notVideo:
            return "That link is not a video file. Use a direct link to an .mp4 or .mov file, or save the video to Photos or Files first."
        case .insecure:
            return "Only https links work."
        case .failed(let m):
            return m
        }
    }
}

/// Every source ends here: a local, playable video file in the temp folder.
enum VideoImport {
    static func copyToTemp(_ src: URL) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("imports", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = src.pathExtension.isEmpty ? "mov" : src.pathExtension
        let dest = dir.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try FileManager.default.copyItem(at: src, to: dest)
        return dest
    }

    /// Files app picker and "Open in LiveWall".
    static func fromFile(_ url: URL) async throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try await validated(try copyToTemp(url))
    }

    /// Direct links to a video file only. Web pages are rejected.
    static func download(_ link: URL) async throws -> URL {
        guard link.scheme?.lowercased() == "https" else { throw VideoImportError.insecure }
        let (tmp, response) = try await URLSession.shared.download(from: link)
        let isVideoType = response.mimeType?.hasPrefix("video/") == true
        let isVideoExt = ["mp4", "mov", "m4v"].contains(link.pathExtension.lowercased())
        guard isVideoType || isVideoExt else { throw VideoImportError.notVideo }
        let named = tmp.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).mp4")
        try FileManager.default.moveItem(at: tmp, to: named)
        return try await validated(try copyToTemp(named))
    }

    static func validated(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let playable = try await asset.load(.isPlayable)
        let hasVideo = try await !asset.loadTracks(withMediaType: .video).isEmpty
        guard playable, hasVideo else { throw VideoImportError.notVideo }
        return url
    }
}
