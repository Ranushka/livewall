import SwiftUI
import UIKit
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var paired = false
    @Published var notes: [Note] = []
    @Published var code: PairCode?
    @Published var error: String?
    @Published var loading = false

    private var api = API()
    private var pendingToken: String?
    private let credsKey = "credentials"

    func start() async {
        if let data = Keychain.get(credsKey), let c = try? JSONDecoder().decode(Credentials.self, from: data) {
            api.credentials = c
        } else {
            await run { let c = try await API().register()
                Keychain.set(self.credsKey, try JSONEncoder().encode(c))
                self.api.credentials = c }
        }
        await requestPush()
        await refresh()
    }

    func requestPush() async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }

    func didReceive(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        pendingToken = token
        Task { await run { try await self.api.setPushToken(token) } }
    }

    func refresh() async {
        guard api.credentials != nil else { return }
        await run {
            self.paired = try await self.api.isPaired()
            if self.paired {
                self.notes = try await self.api.notes()
                self.syncWidget()
            } else {
                self.notes = []
                Shared.save(nil)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    private func syncWidget() {
        if let n = notes.first {
            Shared.save(.init(id: n.id, text: n.text, date: n.date, mine: n.mine))
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func makeCode() async { await run { self.code = try await self.api.createCode() } }
    func join(_ code: String) async { await run { try await self.api.join(code: code); await self.refresh() } }
    func send(_ text: String) async -> Bool {
        var ok = false
        await run { try await self.api.sendNote(text); ok = true; await self.refresh() }
        return ok
    }
    func unpair() async { await run { try await self.api.unpair(); self.code = nil; await self.refresh() } }
    func deleteAccount() async {
        await run {
            try await self.api.deleteAccount()
            Keychain.delete(self.credsKey)
            self.api.credentials = nil
            self.paired = false; self.notes = []; self.code = nil
            Shared.save(nil)
            WidgetCenter.shared.reloadAllTimelines()
        }
        await start()
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        loading = true; defer { loading = false }
        do { try await work(); error = nil } catch { self.error = error.localizedDescription }
    }
}
