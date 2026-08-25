import ActivityKit
import Foundation

struct RetreatActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var phase: String
        var endsAt: Date
    }

    var retreatIndex: Int
}
