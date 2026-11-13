import SwiftUI

struct RootView: View {
    @State private var tab = 0
    @ObservedObject private var maker = WallpaperMaker.shared

    var body: some View {
        TabView(selection: $tab) {
            WallpaperView().tag(0).tabItem { Label("Wallpaper", systemImage: "photo.on.rectangle") }
            PartnerView().tag(1).tabItem { Label("Partner", systemImage: "heart.text.square") }
        }
        .onChange(of: maker.arrivals) { _, _ in tab = 0 }
    }
}
