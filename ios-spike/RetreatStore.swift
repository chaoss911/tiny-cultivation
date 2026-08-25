import Foundation
import UIKit

@MainActor
final class RetreatStore: ObservableObject {
    @Published private(set) var session: RetreatSession?
    @Published private(set) var retreatCount: Int
    @Published var clockWarning = false

    private let defaults = UserDefaults.standard
    private let sessionKey = "spike.retreat.session"
    private let countKey = "spike.retreat.count"
    private let seedKey = "spike.identity.seed"

    init() {
        retreatCount = defaults.integer(forKey: countKey)
        load()
        evaluateClockConsistency()
    }

    var identitySeed: UInt64 {
        if let existing = defaults.object(forKey: seedKey) as? NSNumber {
            return existing.uint64Value
        }
        let seed = UInt64.random(in: UInt64.min...UInt64.max)
        defaults.set(NSNumber(value: seed), forKey: seedKey)
        return seed
    }

    func begin(duration: TimeInterval) -> RetreatSession {
        retreatCount += 1
        defaults.set(retreatCount, forKey: countKey)

        let startedAt = Date()
        let result = DeterministicRNG.result(seed: identitySeed, retreatIndex: retreatCount)
        let newSession = RetreatSession(
            seed: identitySeed,
            retreatIndex: retreatCount,
            startedAt: startedAt,
            endsAt: startedAt.addingTimeInterval(duration),
            monotonicAtStart: ProcessInfo.processInfo.systemUptime,
            result: result
        )
        session = newSession
        persist(newSession)
        return newSession
    }

    func clear() {
        session = nil
        defaults.removeObject(forKey: sessionKey)
    }

    func phaseText(at date: Date = Date()) -> String {
        guard let session else { return "尚未入定" }
        if date >= session.endsAt { return "入定已毕" }

        let total = max(session.endsAt.timeIntervalSince(session.startedAt), 1)
        let elapsed = max(date.timeIntervalSince(session.startedAt), 0)
        let phaseIndex = min(Int((elapsed / total) * 5.0), 4)
        return DeterministicRNG.phase(
            seed: session.seed,
            retreatIndex: session.retreatIndex,
            phaseIndex: phaseIndex
        )
    }

    func evaluateClockConsistency() {
        guard let session else { return }
        let wallElapsed = Date().timeIntervalSince(session.startedAt)
        let monotonicElapsed = ProcessInfo.processInfo.systemUptime - session.monotonicAtStart

        // Reboot makes uptime incomparable, so only flag obvious backward/large divergence cases.
        if wallElapsed < -60 || (monotonicElapsed >= 0 && abs(wallElapsed - monotonicElapsed) > 10 * 60) {
            clockWarning = true
        }
    }

    private func persist(_ session: RetreatSession) {
        if let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: sessionKey)
        }
    }

    private func load() {
        guard
            let data = defaults.data(forKey: sessionKey),
            let decoded = try? JSONDecoder().decode(RetreatSession.self, from: data)
        else { return }
        session = decoded
    }
}
