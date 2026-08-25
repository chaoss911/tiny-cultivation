import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func scheduleRetreatCompletion(for session: RetreatSession) async throws {
        let content = UNMutableNotificationContent()
        content.title = "无名修士出关了"
        content.body = "这一回入定已有结果。"
        content.sound = .default
        content.userInfo = [
            "retreat_index": session.retreatIndex,
            "result": session.result.rawValue
        ]

        let interval = max(session.endsAt.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: "retreat-\(session.retreatIndex)",
            content: content,
            trigger: trigger
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    func cancelAllSpikeNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
