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
    var body: some View {
        ContentUnavailableView("Wallpaper maker", systemImage: "photo.on.rectangle",
                               description: Text("Plug the existing wallpaper maker view in here."))
    }
}
