import Foundation

/// Data shared between the app, the widget and the notification extension via the App Group.
enum Shared {
    static let group = "group.com.ranu.livewall"
    private static let key = "latestNote"
    private static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    struct LatestNote: Codable, Equatable {
        var id: String
        var text: String
        var date: Date
        var mine: Bool
    }

    static func save(_ note: LatestNote?) {
        if let note, let data = try? JSONEncoder().encode(note) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    static func load() -> LatestNote? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LatestNote.self, from: data)
    }
}
