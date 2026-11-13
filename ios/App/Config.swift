import Foundation

enum Config {
    /// Your deployed Worker URL (shown after `pnpm deploy`).
    static let baseURL = URL(string: "https://livewall.YOUR-SUBDOMAIN.workers.dev")!
}
