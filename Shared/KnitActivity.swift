import ActivityKit
import Foundation

struct KnitActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var row: Int
        var stitch: Int
        var target: Int
    }
    var projectID: UUID
    var partID: UUID
    var counterID: UUID
    var name: String
}
