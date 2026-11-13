import SwiftUI

struct PaywallView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles.rectangle.stack").font(.system(size: 56)).foregroundStyle(.tint)
            Text("Unlock LiveWall").font(.title.bold())
            Text("You've used your \(Store.freeLimit) free wallpapers. Unlock unlimited live wallpapers with a one-time purchase.\n\nPartner notes are always free.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button {
                Task { await store.purchase() }
            } label: {
                Text("Unlock for \(store.product?.displayPrice ?? "$2.99")").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            Button("Restore Purchases") { Task { await store.restore() } }
            if let m = store.message { Text(m).font(.footnote).foregroundStyle(.red) }
        }
        .padding(24)
        .onChange(of: store.isUnlocked) { _, unlocked in if unlocked { dismiss() } }
    }
}
