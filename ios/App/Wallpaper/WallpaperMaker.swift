import AVFoundation
import SwiftUI

@MainActor
final class WallpaperMaker: ObservableObject {
    static let shared = WallpaperMaker()

    enum Phase: Equatable { case idle, loading, saving, saved }

    @Published private(set) var sourceURL: URL?
    @Published private(set) var videoSize: CGSize = .zero   // as displayed (rotation applied)
    @Published private(set) var duration: Double = 0
    @Published var start: Double = 0 { didSet { restartLoop() } }
    @Published var zoom: CGFloat = 1 { didSet { clampPan() } }
    @Published var pan: CGSize = .zero
    @Published var phase: Phase = .idle
    @Published var error: String?
    /// Bumps when a video arrives from outside the screen (e.g. "Open in LiveWall").
    @Published private(set) var arrivals = 0

    let player = AVPlayer()
    private var timeObserver: Any?

    var clipLength: Double { min(LivePhotoExporter.clipSeconds, duration) }
    var maxStart: Double { max(0, duration - LivePhotoExporter.clipSeconds) }
    var framing: Framing { Framing(zoom: zoom, pan: pan) }

    private init() {
        player.isMuted = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else { return }
            if time.seconds >= self.start + self.clipLength { self.restartLoop() }
        }
    }

    // MARK: Sources

    func load(_ work: @escaping () async throws -> URL) async {
        phase = .loading; error = nil
        do { try await use(try await work()) }
        catch { self.error = error.localizedDescription; phase = sourceURL == nil ? .idle : .idle }
    }

    func receive(fileURL: URL) async {
        await load { try await VideoImport.fromFile(fileURL) }
        arrivals += 1
    }

    private func use(_ url: URL) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoImportError.notVideo }
        let (natural, pref, length) = try await (track.load(.naturalSize), track.load(.preferredTransform), asset.load(.duration))
        let o = natural.applying(pref)
        videoSize = CGSize(width: abs(o.width), height: abs(o.height))
        duration = length.seconds
        sourceURL = url
        zoom = 1; pan = .zero; start = 0
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        restartLoop()
        phase = .idle
    }

    private func restartLoop() {
        guard sourceURL != nil else { return }
        player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    // MARK: Framing

    /// Most the video may move (render pixels) before an edge of the frame shows.
    func panLimit(zoom z: CGFloat) -> CGSize {
        guard videoSize.width > 0 else { return .zero }
        let r = LivePhotoExporter.renderSize
        let s = max(r.width / videoSize.width, r.height / videoSize.height) * z
        return CGSize(width: max(0, (videoSize.width * s - r.width) / 2),
                      height: max(0, (videoSize.height * s - r.height) / 2))
    }

    func setPan(_ p: CGSize) {
        let l = panLimit(zoom: zoom)
        pan = CGSize(width: min(max(p.width, -l.width), l.width), height: min(max(p.height, -l.height), l.height))
    }

    private func clampPan() { setPan(pan) }

    // MARK: Save

    /// Caller checks the paywall first. Returns true when the Live Photo reached Photos.
    func save() async -> Bool {
        guard let sourceURL else { return false }
        phase = .saving; error = nil
        do {
            let output = try await LivePhotoExporter.export(source: sourceURL, start: start, framing: framing)
            try await LivePhotoExporter.saveToPhotos(output)
            phase = .saved
            return true
        } catch {
            self.error = error.localizedDescription
            phase = .idle
            return false
        }
    }
}
