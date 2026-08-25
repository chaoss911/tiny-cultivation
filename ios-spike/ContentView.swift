import SwiftUI
import UserNotifications

struct ContentView: View {
    @StateObject private var store = RetreatStore()
    @State private var permissionStatus = "unknown"
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 24) {
            Text("无名")
                .font(.title2)
            Text("凡人")
                .foregroundStyle(.secondary)

            if let session = store.session {
                if session.isComplete {
                    Text(session.result.rawValue)
                        .font(.largeTitle)
                    Text(session.result.detail)
                        .multilineTextAlignment(.center)

                    if store.clockWarning {
                        Text("时序不明")
                            .font(.caption)
                    }

                    Button("再次入定") {
                        Task { await beginRetreat() }
                    }
                } else {
                    Text(store.phaseText())
                    Text(timerInterval: Date()...session.endsAt, countsDown: true)
                        .monospacedDigit()
                }
            } else {
                Button("入定") {
                    Task { await beginRetreat() }
                }
            }

            Text("通知：\(permissionStatus)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(32)
        .task {
            await refreshPermissionStatus()
        }
    }

    private func beginRetreat() async {
        errorText = nil

        do {
            var status = await NotificationManager.shared.authorizationStatus()
            if status == .notDetermined {
                _ = try await NotificationManager.shared.requestAuthorization()
                status = await NotificationManager.shared.authorizationStatus()
            }
            permissionStatus = String(describing: status)

            // Intentionally short for physical-device spike testing.
            let session = store.begin(duration: 120)

            if status == .authorized || status == .provisional || status == .ephemeral {
                try await NotificationManager.shared.scheduleRetreatCompletion(for: session)
            }

            if #available(iOS 16.2, *) {
                try LiveActivityManager.shared.start(for: session, phase: store.phaseText())
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func refreshPermissionStatus() async {
        let status = await NotificationManager.shared.authorizationStatus()
        permissionStatus = String(describing: status)
    }
}
