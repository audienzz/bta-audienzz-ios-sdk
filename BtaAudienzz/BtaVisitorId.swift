import Foundation

/// Manages the persistent visitor UUID stored in UserDefaults.
enum BtaVisitorId {

    private static let key = "org.audienzz.bta.visitor_id"

    /// Returns the existing visitor ID or creates and persists a new UUID.
    static func getOrCreate() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key) {
            return existing
        }
        let newId = UUID().uuidString
        defaults.set(newId, forKey: key)
        return newId
    }
}
