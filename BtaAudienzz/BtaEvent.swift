import Foundation

struct BtaEvent {
    let type: BtaEventType
    let publisherId: String?
    let btaFeedId: String
    var visitorId: String        // mutable — filled in by BtaEventTracker before sending
    let sessionId: String
    let timestamp: Date
    let index: Int?

    /// Convenience initialiser. `visitorId` and `sessionId` are filled by ``BtaEventTracker``.
    init(type: BtaEventType, btaFeedId: String, index: Int? = nil) {
        self.type        = type
        self.publisherId = BtaSdk.publisherId
        self.btaFeedId   = btaFeedId
        self.visitorId   = ""    // overwritten by BtaEventTracker.track(_:)
        self.sessionId   = BtaEventTracker.shared.sessionId
        self.timestamp   = Date()
        self.index       = index
    }

    /// Serialises the event to a CloudEvents 1.0 dictionary ready for JSON encoding.
    func toCloudEventDict() -> [String: Any] {
        var data: [String: Any] = [
            "publisherId": publisherId ?? "",
            "btaFeedId":   btaFeedId,
            "visitorId":   visitorId,
            "sessionId":   sessionId,
        ]
        if let i = index { data["index"] = i }

        let formatter = ISO8601DateFormatter()
        return [
            "specversion":     "1.0",
            "type":            type.rawValue,
            "source":          "mobile-sdk",
            "id":              UUID().uuidString,
            "time":            formatter.string(from: timestamp),
            "datacontenttype": "application/json",
            "data":            data,
        ]
    }
}
