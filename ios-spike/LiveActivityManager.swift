import ActivityKit
import Foundation

@available(iOS 16.2, *)
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    func start(for session: RetreatSession, phase: String) throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = RetreatActivityAttributes(retreatIndex: session.retreatIndex)
        let state = RetreatActivityAttributes.ContentState(phase: phase, endsAt: session.endsAt)
        let content = ActivityContent(state: state, staleDate: session.endsAt)

        _ = try Activity.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
    }

    func endAll() async {
        for activity in Activity<RetreatActivityAttributes>.activities {
            let final = RetreatActivityAttributes.ContentState(
                phase: "入定已毕",
                endsAt: Date()
            )
            await activity.end(
                ActivityContent(state: final, staleDate: nil),
                dismissalPolicy: .default
            )
        }
    }
}
