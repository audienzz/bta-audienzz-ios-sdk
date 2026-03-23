import Foundation

/// Payload delivered when an article is clicked in the BTA feed.
public struct ArticleClickPayload {

    /// The feed ID that triggered the event.
    public let btaFeedId: String

    /// Zero-based position of the item in the feed.
    public let index: Int

    /// Raw dictionary from the BTA JS SDK describing the article.
    public let article: [String: Any]

    /// Article destination URL.
    public let url: String

    /// Article title.
    public let title: String

    init(body: [String: Any]) {
        btaFeedId = body["btaFeedId"] as? String ?? ""
        index     = body["index"]     as? Int    ?? -1
        article   = body["article"]   as? [String: Any] ?? [:]
        url   = article["url"]   as? String ?? ""
        title = article["title"] as? String ?? ""
    }
}
