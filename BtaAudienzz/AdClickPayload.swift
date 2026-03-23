import Foundation

/// Payload delivered when an ad or native ad is clicked in the BTA feed.
/// Covers both display ads (`onAdClick`) and native ads (`onNativeAdClick`).
public struct AdClickPayload {

    /// The feed ID that triggered the event.
    public let btaFeedId: String

    /// Zero-based position of the item in the feed.
    public let index: Int

    /// Raw dictionary from the BTA JS SDK describing the ad unit.
    public let adUnit: [String: Any]

    /// Ad destination URL. Empty string if not provided by the JS SDK.
    ///
    /// Resolution order (first non-empty wins):
    /// 1. Top-level `url` — extracted in the JS template from common adUnit fields
    ///    (`ad.clickUrl`, `ad.url`, `clickUrl`, `url`, `destinationUrl`, `targetUrl`, `href`).
    /// 2. `adUnit["url"]` — direct fallback.
    public let url: String

    init(body: [String: Any]) {
        btaFeedId = body["btaFeedId"] as? String ?? ""
        index     = body["index"]     as? Int    ?? -1
        adUnit    = body["adUnit"]    as? [String: Any] ?? [:]
        let topUrl = body["url"] as? String ?? ""
        url = topUrl.isEmpty ? (adUnit["url"] as? String ?? "") : topUrl
    }
}
