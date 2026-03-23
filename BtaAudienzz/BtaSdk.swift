import Foundation

/// Entry point for the BtaAudienzz SDK.
///
/// Call ``BtaSdk/initialize(publisherId:)`` once in
/// `AppDelegate.application(_:didFinishLaunchingWithOptions:)` before using any SDK components.
public final class BtaSdk {

    /// The publisher identifier supplied during initialisation.
    public private(set) static var publisherId: String?

    /// Initialise the SDK. Must be called before creating a ``BtaFeedView``.
    ///
    /// - Parameter publisherId: Your Audienzz publisher ID.
    public static func initialize(publisherId: String) {
        Self.publisherId = publisherId
        BtaEventTracker.shared.initialize()
    }

    private init() {}
}
