import Foundation
import WebKit

// MARK: - BtaJsBridge

/// Internal JS-to-Swift bridge for the BTA feed WebView.
///
/// Registered as a `WKScriptMessageHandler` for each named message channel.
/// JavaScript calls `window.webkit.messageHandlers.<name>.postMessage(data)`.
///
/// **Retain-cycle note**: `WKUserContentController` strongly retains its handlers.
/// Always register the `WeakScriptMessageHandler` wrapper, not `BtaJsBridge` directly.
final class BtaJsBridge: NSObject {

    /// Names that must be registered on `WKUserContentController` for every load.
    static let messageHandlerNames: [String] = [
        "onArticleClick",
        "onAdClick",
        "onNativeAdClick",
        "onAdImpression",
        "onArticleImpression",
        "onContentHeightChanged",
        "onFeedReady",
        "onFeedError",
    ]

    // MARK: Callbacks set by BtaFeedView

    var onHeightChanged: ((CGFloat) -> Void)?
    var onFeedLoaded: (() -> Void)?
    var onFeedError: ((String) -> Void)?
    /// Called on the main thread on any article/ad click — the user is navigating away
    /// (SDK web view or a publisher-handled click), so the feed should suppress its next reload.
    var onWillNavigateAway: (() -> Void)?

    // MARK: Private

    private let btaFeedId: String
    private weak var delegate: BtaFeedDelegate?
    private weak var feedView: BtaFeedView?

    init(btaFeedId: String, delegate: BtaFeedDelegate?, feedView: BtaFeedView) {
        self.btaFeedId = btaFeedId
        self.delegate  = delegate
        self.feedView  = feedView
    }

    // MARK: - Helpers

    private func handleArticleClick(body: [String: Any]) {
        let payload = ArticleClickPayload(body: body)
        trackEvent(.articleClick, index: payload.index)

        // The user is navigating away (whether we open the web view or the publisher handles
        // it themselves), so suppress the reload that fires when the feed reappears.
        onWillNavigateAway?()

        let handled = feedView.map { view in
            delegate?.btaFeedView(view, didClickArticle: payload) ?? false
        } ?? false

        if !handled {
            openInWebViewController(urlString: payload.url)
        }
    }

    private func handleAdClick(body: [String: Any]) {
        let payload = AdClickPayload(body: body)
        print("[BtaJsBridge] Ad click payload url: \(payload.url)")
        trackEvent(.adClick, index: payload.index)

        onWillNavigateAway?()

        let handled = feedView.map { view in
            delegate?.btaFeedView(view, didClickAd: payload) ?? false
        } ?? false

        if !handled {
            openInWebViewController(urlString: payload.url)
        }
    }

    private func openInWebViewController(urlString: String) {
        guard !urlString.isEmpty, let url = URL(string: urlString) else { return }

        guard let feedView, let presenter = feedView.closestViewController() else { return }
        let webVC = BtaWebViewController(url: url)
        let nav = UINavigationController(rootViewController: webVC)
        nav.modalPresentationStyle = .fullScreen
        presenter.present(nav, animated: true)
    }

    private func trackEvent(_ type: BtaEventType, index: Int? = nil) {
        BtaEventTracker.shared.track(BtaEvent(type: type, btaFeedId: btaFeedId, index: index))
    }
}

// MARK: - WKScriptMessageHandler

extension BtaJsBridge: WKScriptMessageHandler {

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        // WKScriptMessageHandler is called on the main thread.
        switch message.name {

        case "onFeedReady":
            break // onFeedViewDidLoad fires on first non-zero height, not on JS SDK init

        case "onFeedError":
            let msg = message.body as? String ?? "Feed error"
            onFeedError?(msg)

        case "onContentHeightChanged":
            // JS sends a plain number, not a dictionary.
            let height: CGFloat
            if let d = message.body as? Double {
                height = CGFloat(d)
            } else if let n = message.body as? NSNumber {
                height = CGFloat(n.doubleValue)
            } else {
                return
            }
            onHeightChanged?(height)

        default:
            guard let body = message.body as? [String: Any] else { return }
            switch message.name {
            case "onArticleClick":
                handleArticleClick(body: body)
            case "onAdClick", "onNativeAdClick":
                handleAdClick(body: body)
            case "onAdImpression":
                trackEvent(.adImpression, index: body["index"] as? Int)
            case "onArticleImpression":
                trackEvent(.articleImpression, index: body["index"] as? Int)
            default:
                break
            }
        }
    }
}

// MARK: - WeakScriptMessageHandler

/// Breaks the strong-reference cycle introduced by `WKUserContentController` retaining handlers.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {

    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
