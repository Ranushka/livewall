import StoreKit
import SwiftUI

/// 2 free wallpapers, then a one-time non-consumable unlock. Partner notes are never gated.
@MainActor
final class Store: ObservableObject {
    static let productID = "com.example.livewall.unlock"
    static let freeLimit = 2
    private static let countKey = "wallpapersMade"

    @Published private(set) var product: Product?
    @Published private(set) var isUnlocked = false
    @Published private(set) var wallpapersMade = UserDefaults.standard.integer(forKey: Store.countKey)
    @Published var message: String?

    private var updates: Task<Void, Never>?

    var canMakeWallpaper: Bool { isUnlocked || wallpapersMade < Self.freeLimit }
    var freeLeft: Int { max(0, Self.freeLimit - wallpapersMade) }

    init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates { await self?.handle(result) }
        }
    }
    deinit { updates?.cancel() }

    func start() async {
        product = try? await Product.products(for: [Self.productID]).first
        await refreshEntitlement()
    }

    /// Call after a wallpaper has been saved successfully.
    func recordWallpaperMade() {
        wallpapersMade += 1
        UserDefaults.standard.set(wallpapersMade, forKey: Self.countKey)
    }

    func purchase() async {
        guard let product else { message = "Store unavailable. Try again later."; return }
        do {
            switch try await product.purchase() {
            case .success(let result): await handle(result)
            case .pending: message = "Purchase pending approval."
            case .userCancelled: break
            @unknown default: break
            }
        } catch { message = error.localizedDescription }
    }

    func restore() async {
        do { try await AppStore.sync() } catch { message = error.localizedDescription }
        await refreshEntitlement()
        if !isUnlocked { message = "No previous purchase found." }
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let tx) = result else { message = "Purchase couldn't be verified."; return }
        await tx.finish()
        await refreshEntitlement()
    }

    private func refreshEntitlement() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.productID == Self.productID, tx.revocationDate == nil { unlocked = true }
        }
        isUnlocked = unlocked
    }
}
