import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            WallpaperView().tabItem { Label("Wallpaper", systemImage: "photo.on.rectangle") }
            PartnerView().tabItem { Label("Partner", systemImage: "heart.text.square") }
        }
    }
}

/// Placeholder: drop the existing live-wallpaper maker view in here.
struct WallpaperView: View {
    @EnvironmentObject var store: Store
    @State private var showPaywall = false

    var body: some View {
        VStack(spacing: 16) {
            ContentUnavailableView("Wallpaper maker", systemImage: "photo.on.rectangle",
                                   description: Text("Plug the existing wallpaper maker view in here."))
            if !store.isUnlocked { Text("\(store.freeLeft) free wallpapers left").font(.footnote).foregroundStyle(.secondary) }
            // Wire up: before saving, `if store.canMakeWallpaper { save(); store.recordWallpaperMade() } else { showPaywall = true }`
            Button("Restore Purchases") { Task { await store.restore() } }.font(.footnote)
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }
}
