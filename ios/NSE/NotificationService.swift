import UserNotifications
import WidgetKit

/// Runs when a partner's note push arrives: saves the note so the widget can show it.
final class NotificationService: UNNotificationServiceExtension {
    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        let info = request.content.userInfo
        if let id = info["noteId"] as? String, let text = info["text"] as? String {
            Shared.save(.init(id: id, text: text, date: Date(), mine: false))
            WidgetCenter.shared.reloadAllTimelines()
        }
        contentHandler(request.content)
    }
}
