import Foundation

/// Delegate protocol for ``BtaFeedView`` events.
///
/// All methods have default no-op implementations so you only need to implement what you need.
public protocol BtaFeedDelegate: AnyObject {

    /// Called when the user taps an article in the feed.
    ///
    /// Return `true` to handle the URL yourself.
    /// Return `false` (default) to let the SDK open the URL in a full-screen ``BtaWebViewController``.
    func btaFeedView(_ view: BtaFeedView, didClickArticle payload: ArticleClickPayload) -> Bool

    /// Called when the user taps an ad.
    ///
    /// Return `true` to handle the URL yourself.
    /// Return `false` (default) to let the SDK open the URL in a full-screen ``BtaWebViewController``.
    func btaFeedView(_ view: BtaFeedView, didClickAd payload: AdClickPayload) -> Bool

    /// Called once the feed widget has successfully initialised.
    func btaFeedViewDidLoad(_ view: BtaFeedView)

    /// Called when the feed encounters an error.
    func btaFeedView(_ view: BtaFeedView, didFailWithError error: String)
}

public extension BtaFeedDelegate {
    func btaFeedView(_ view: BtaFeedView, didClickArticle payload: ArticleClickPayload) -> Bool { false }
    func btaFeedView(_ view: BtaFeedView, didClickAd payload: AdClickPayload) -> Bool { false }
    func btaFeedViewDidLoad(_ view: BtaFeedView) {}
    func btaFeedView(_ view: BtaFeedView, didFailWithError error: String) {}
}
