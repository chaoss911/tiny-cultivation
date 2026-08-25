import Foundation

struct RetreatSession: Codable, Equatable {
    let seed: UInt64
    let retreatIndex: Int
    let startedAt: Date
    let endsAt: Date
    let monotonicAtStart: TimeInterval
    let result: RetreatResult

    var isComplete: Bool { Date() >= endsAt }
}

enum RetreatResult: String, Codable, CaseIterable {
    case breakthrough = "破境"
    case bottleneck = "瓶颈"
    case encounter = "奇遇"
    case deviation = "走火入魔"

    var detail: String {
        switch self {
        case .breakthrough: return "气机贯通，境界向前一步。"
        case .bottleneck: return "似有所悟，却仍隔着一层。"
        case .encounter: return "神游之间，似乎遇见了什么。"
        case .deviation: return "气息一乱，这次入定没有善终。"
        }
    }
}

enum DeterministicRNG {
    // SplitMix64: tiny, deterministic, and sufficient for a product spike.
    static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    static func value(seed: UInt64, namespace: UInt64, index: Int) -> UInt64 {
        mix(seed ^ namespace ^ UInt64(index))
    }

    static func result(seed: UInt64, retreatIndex: Int) -> RetreatResult {
        let namespace: UInt64 = 0x726573756C74 // "result"
        let roll = value(seed: seed, namespace: namespace, index: retreatIndex)
        return RetreatResult.allCases[Int(roll % UInt64(RetreatResult.allCases.count))]
    }

    // Deliberately independent from the result namespace.
    static func phase(seed: UInt64, retreatIndex: Int, phaseIndex: Int) -> String {
        let namespace: UInt64 = 0x7068617365 // "phase"
        let roll = value(seed: seed ^ UInt64(retreatIndex), namespace: namespace, index: phaseIndex)
        let phases = ["气息渐稳", "物我两忘", "神思渐远", "静坐无言", "一念不起"]
        return phases[Int(roll % UInt64(phases.count))]
    }
}
