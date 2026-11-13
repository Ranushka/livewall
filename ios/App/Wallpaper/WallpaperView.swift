import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct WallpaperView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var maker = WallpaperMaker.shared

    @State private var pickerItem: PhotosPickerItem?
    @State private var showFiles = false
    @State private var showLink = false
    @State private var showPaywall = false
    @State private var showSaved = false
    @State private var panAtStart: CGSize = .zero

    private var render: CGSize { LivePhotoExporter.renderSize }

    var body: some View {
        NavigationStack {
            Group {
                if maker.sourceURL == nil { emptyState } else { editor }
            }
            .navigationTitle("Wallpaper")
            .toolbar {
                if maker.sourceURL != nil { ToolbarItem(placement: .topBarTrailing) { sourceMenu(label: "Change video") } }
            }
            .overlay { if maker.phase == .loading { ProgressView("Loading video…").padding().background(.regularMaterial, in: .rect(cornerRadius: 12)) } }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                await maker.load {
                    guard let video = try await item.loadTransferable(type: PickedVideo.self) else { throw VideoImportError.notVideo }
                    return try await VideoImport.validated(video.url)
                }
                pickerItem = nil
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie]) { result in
            if case .success(let url) = result { Task { await maker.load { try await VideoImport.fromFile(url) } } }
            else if case .failure(let e) = result { maker.error = e.localizedDescription }
        }
        .sheet(isPresented: $showLink) { LinkSheet() }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .alert("Saved to Photos", isPresented: $showSaved) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Now set it: Settings → Wallpaper → Add New Wallpaper → Photos → pick the Live Photo. Turn on Live Photo, then press and hold the Lock Screen to play it.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { maker.error != nil }, set: { if !$0 { maker.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(maker.error ?? "") }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            ContentUnavailableView("Pick a video", systemImage: "play.rectangle",
                                   description: Text("Choose a video from your phone. It becomes a Live Photo that moves on your Lock Screen."))
            VStack(spacing: 12) {
                PhotosPicker(selection: $pickerItem, matching: .videos) {
                    Label("Photos library", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent)
                Button { showFiles = true } label: { Label("Files", systemImage: "folder").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                Button { showLink = true } label: { Label("Paste a video link", systemImage: "link").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)
            Text("Videos from TikTok, YouTube or Pinterest: save the video to Photos or Files in that app, then pick it here. You can also share a video file to LiveWall.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            freeLeftNote
        }
        .padding(24)
    }

    private func sourceMenu(label: String) -> some View {
        Menu {
            PhotosPicker(selection: $pickerItem, matching: .videos) { Label("Photos library", systemImage: "photo.on.rectangle") }
            Button { showFiles = true } label: { Label("Files", systemImage: "folder") }
            Button { showLink = true } label: { Label("Paste a video link", systemImage: "link") }
        } label: { Label(label, systemImage: "ellipsis.circle") }
    }

    // MARK: Editor

    private var editor: some View {
        ScrollView {
            VStack(spacing: 16) {
                GeometryReader { geo in
                    let k = geo.size.width / render.width   // render px -> screen points
                    PlayerView(player: maker.player)
                        .scaleEffect(maker.zoom)
                        .offset(x: maker.pan.width * k, y: maker.pan.height * k)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .contentShape(Rectangle())
                        .gesture(DragGesture()
                            .onChanged { v in maker.setPan(CGSize(width: panAtStart.width + v.translation.width / k,
                                                                 height: panAtStart.height + v.translation.height / k)) }
                            .onEnded { _ in panAtStart = maker.pan })
                        .simultaneousGesture(MagnifyGesture()
                            .onChanged { v in maker.zoom = min(max(1, v.magnification * zoomAtStart), 4) }
                            .onEnded { _ in zoomAtStart = maker.zoom })
                }
                .aspectRatio(render.width / render.height, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 24))
                .frame(maxHeight: 520)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Zoom").font(.footnote).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { maker.zoom }, set: { maker.zoom = $0; zoomAtStart = $0 }), in: 1...4)
                }
                if maker.maxStart > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Starts at \(maker.start, format: .number.precision(.fractionLength(1))) s (3 second clip)")
                            .font(.footnote).foregroundStyle(.secondary)
                        Slider(value: $maker.start, in: 0...maker.maxStart)
                    }
                }
                Button(action: save) {
                    Group {
                        if maker.phase == .saving { ProgressView() } else { Text("Save Live Photo") }
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(maker.phase == .saving)
                freeLeftNote
            }
            .padding(24)
        }
        .onAppear { panAtStart = maker.pan; zoomAtStart = maker.zoom }
    }

    @State private var zoomAtStart: CGFloat = 1

    @ViewBuilder private var freeLeftNote: some View {
        VStack(spacing: 4) {
            if !store.isUnlocked { Text("\(store.freeLeft) free wallpapers left").font(.footnote).foregroundStyle(.secondary) }
            Button("Restore Purchases") { Task { await store.restore() } }.font(.footnote)
        }
    }

    private func save() {
        guard store.canMakeWallpaper else { showPaywall = true; return }
        Task {
            if await maker.save() {
                store.recordWallpaperMade()
                showSaved = true
            }
        }
    }
}

// MARK: Link sheet

private struct LinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/video.mp4", text: $text)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    PasteButton(payloadType: URL.self) { urls in if let u = urls.first { text = u.absoluteString } }
                } footer: {
                    Text("Use a direct link to a video file (.mp4 or .mov). Links to TikTok, YouTube or Pinterest pages do not work. Save the video to Photos or Files in that app instead.")
                }
                Button(busy ? "Downloading…" : "Use this video") { go() }
                    .disabled(busy || URL(string: text.trimmingCharacters(in: .whitespaces)) == nil)
            }
            .navigationTitle("Video link")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }

    private func go() {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)) else { return }
        busy = true
        Task {
            await WallpaperMaker.shared.load { try await VideoImport.download(url) }
            busy = false
            if WallpaperMaker.shared.error == nil { dismiss() }
        }
    }
}

// MARK: Player

struct PlayerView: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerUIView {
        let v = PlayerUIView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PlayerUIView, context: Context) {}
}

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
