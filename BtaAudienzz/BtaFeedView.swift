import UIKit
import WebKit

/// BTA (Below The Article) Feed View.
///
/// Embeds the Audienzz BTA feed widget in a `WKWebView`, auto-resizes to fit its
/// content, and automatically tracks analytics events.
///
/// ## Basic usage
///
/// ```swift
/// // AppDelegate.application(_:didFinishLaunchingWithOptions:) — once
/// BtaSdk.initialize(publisherId: "your-publisher-id")
///
/// // Set delegate (e.g. in viewDidLoad)
/// btaFeedView.delegate = self
///
/// // Load every time the screen appears
/// override func viewWillAppear(_ animated: Bool) {
///     super.viewWillAppear(animated)
///     btaFeedView.load(btaFeedId: "your-bta-feed-id")
/// }
///
/// // Tear down
/// override func viewWillDisappear(_ animated: Bool) {
///     super.viewWillDisappear(animated)
///     btaFeedView.destroy()
/// }
/// ```
public final class BtaFeedView: UIView {

    // MARK: - Public

    /// Delegate for feed events. Can be set or replaced at any time.
    public weak var delegate: BtaFeedDelegate?

    // MARK: - Private

    private var webView: WKWebView!
    private var heightConstraint: NSLayoutConstraint!

    private var currentFeedId: String?
    private var viewableImpressionFired = false

    /// When `true`, the next ``load(btaFeedId:debug:mockRecommendations:)`` call with the same
    /// feed ID is skipped. Set just before presenting ``BtaWebViewController`` so the
    /// `viewWillAppear → load()` cycle on return does not reload the feed.
    private var suppressNextLoad = false

    private var viewabilityTimer: Timer?
    private var bridge: BtaJsBridge?

    // MARK: - Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupWebView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupWebView()
    }

    // MARK: - Public API

    /// Load the BTA feed. Call every time the publisher's screen appears
    /// (e.g. from `viewWillAppear`).
    ///
    /// If the user is returning from ``BtaWebViewController`` for the same feed ID,
    /// the reload is suppressed automatically — the WebView keeps its existing content.
    ///
    /// Fires a `btafeed.pageview` analytics event on every real load.
    ///
    /// - Parameters:
    ///   - btaFeedId: The feed identifier provided by Audienzz.
    ///   - debug: Enable feed debug logging (**do not use in production**).
    ///   - mockRecommendations: Show mock recommendations (**do not use in production**).
    public func load(
        btaFeedId: String,
        debug: Bool = false,
        mockRecommendations: Bool = false
    ) {
        // Suppress reload when returning from the ad/article WebView for the same feed.
        // Still re-attach bridge handlers — destroy() may have removed them when the
        // fullscreen modal caused viewWillDisappear to fire on the parent view controller.
        if suppressNextLoad && btaFeedId == currentFeedId {
            suppressNextLoad = false
            rebuildBridge(btaFeedId: btaFeedId)
            return
        }
        suppressNextLoad = false

        currentFeedId = btaFeedId
        viewableImpressionFired = false
        updateHeight(0)

        BtaEventTracker.shared.track(BtaEvent(type: .pageView, btaFeedId: btaFeedId))

        startViewabilityTimer()
        rebuildBridge(btaFeedId: btaFeedId)

        let html = buildHTML(feedId: btaFeedId, debug: debug, mockRecommendations: mockRecommendations)
        webView.loadHTMLString(html, baseURL: URL(string: Self.cdnBaseURL))
    }

    /// Release resources. Call from `viewWillDisappear` or the owning object's `deinit`.
    public func destroy() {
        stopViewabilityTimer()
        webView.stopLoading()
        removeBridgeHandlers()
        bridge = nil
    }

    // MARK: - Intrinsic content size

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: heightConstraint.constant)
    }

    // MARK: - Setup

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        // Allow inline media and autoplay for video/audio ad units.
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        // Disable internal scrolling; the parent UIScrollView handles all scrolling.
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(webView)

        heightConstraint = webView.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightConstraint,
        ])
    }

    // MARK: - Bridge management

    private func rebuildBridge(btaFeedId: String) {
        removeBridgeHandlers()

        let newBridge = BtaJsBridge(btaFeedId: btaFeedId, delegate: delegate, feedView: self)

        newBridge.onHeightChanged = { [weak self] height in
            self?.updateHeight(height)
            if self?.viewableImpressionFired == false {
                self?.checkViewabilityAndTrack()
            }
        }
        newBridge.onFeedLoaded = { [weak self] in
            guard let self else { return }
            self.delegate?.btaFeedViewDidLoad(self)
        }
        newBridge.onFeedError = { [weak self] error in
            guard let self else { return }
            self.delegate?.btaFeedView(self, didFailWithError: error)
        }
        newBridge.onWillOpenWebView = { [weak self] in
            self?.suppressNextLoad = true
        }

        // Use the weak wrapper to avoid the WKUserContentController retain cycle.
        let weakHandler = WeakScriptMessageHandler(newBridge)
        let ucc = webView.configuration.userContentController
        BtaJsBridge.messageHandlerNames.forEach { name in
            ucc.add(weakHandler, name: name)
        }

        bridge = newBridge
    }

    private func removeBridgeHandlers() {
        let ucc = webView.configuration.userContentController
        BtaJsBridge.messageHandlerNames.forEach { name in
            ucc.removeScriptMessageHandler(forName: name)
        }
    }

    // MARK: - Height

    private func updateHeight(_ height: CGFloat) {
        guard heightConstraint.constant != height else { return }
        heightConstraint.constant = height
        invalidateIntrinsicContentSize()
        // Animate height changes to avoid a jarring snap.
        UIView.animate(withDuration: 0.15) { self.superview?.layoutIfNeeded() }
    }

    // MARK: - Viewable impression

    /// Polls visibility at 100 ms intervals until ≥50 % of the view is on screen.
    private func startViewabilityTimer() {
        stopViewabilityTimer()
        viewabilityTimer = Timer.scheduledTimer(
            withTimeInterval: 0.1,
            repeats: true
        ) { [weak self] _ in
            self?.checkViewabilityAndTrack()
        }
    }

    private func stopViewabilityTimer() {
        viewabilityTimer?.invalidate()
        viewabilityTimer = nil
    }

    private func checkViewabilityAndTrack() {
        guard let feedId = currentFeedId, !viewableImpressionFired else {
            stopViewabilityTimer()
            return
        }
        guard let window else { return }

        let frameInWindow = convert(bounds, to: window)
        let intersection = frameInWindow.intersection(window.bounds)
        guard !intersection.isNull, !intersection.isEmpty else { return }

        let visibleArea = intersection.width * intersection.height
        let totalArea   = bounds.width * bounds.height
        guard totalArea > 0, visibleArea / totalArea >= 0.5 else { return }

        viewableImpressionFired = true
        stopViewabilityTimer()
        BtaEventTracker.shared.track(BtaEvent(type: .viewableImpression, btaFeedId: feedId))
    }

    // MARK: - HTML template

    private func buildHTML(feedId: String, debug: Bool, mockRecommendations: Bool) -> String {
        let debugLine = debug ? "debug: true," : ""
        let mockLine  = mockRecommendations ? "mockRecommendations: true," : ""

        // NOTE: On iOS, WKWebView JS height is already in UIKit points (no scale factor needed).
        // NOTE: Uses plain function() syntax and var for broad WebView compatibility.
        return """
        <!doctype html>
        <html lang="en">
        <head>
            <base target="_parent" />
            <meta charset="UTF-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0" />
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body { overflow: hidden; width: 100%; }
            </style>
        </head>
        <body>
            <script async src="\(Self.cdnBaseURL)bta-feed/index.js"></script>
            <script type="text/javascript">
                window.adnzBtaFeed = window.adnzBtaFeed || {};
                window.adnzBtaFeed.queue = window.adnzBtaFeed.queue || [];
                window.adnzBtaFeed.queue.push(function() {
                    window.adnzBtaFeed.start({
                        btaFeedId: '\(feedId)',
                        webview: true,
                        \(debugLine)
                        \(mockLine)
                        onArticleClick: function(payload) {
                            payload.event.preventDefault();
                            window.webkit.messageHandlers.onArticleClick.postMessage({
                                article: payload.article,
                                btaFeedId: payload.btaFeedId,
                                index: payload.index
                            });
                        },
                        onAdClick: function(payload) {
                            payload.event.preventDefault();
                            var unit = payload.adUnit || {};
                            var ad   = unit.ad || {};
                            var url = ad.clickUrl || ad.url
                                   || unit.clickUrl || unit.url || unit.destinationUrl
                                   || unit.targetUrl || unit.href
                                   || payload.clickUrl || payload.url || '';
                            window.webkit.messageHandlers.onAdClick.postMessage({
                                adUnit: unit,
                                url: url,
                                btaFeedId: payload.btaFeedId,
                                index: payload.index
                            });
                        },
                        onNativeAdClick: function(payload) {
                            payload.event.preventDefault();
                            var unit = payload.adUnit || {};
                            var ad   = unit.ad || {};
                            var url = ad.clickUrl || ad.url
                                   || unit.clickUrl || unit.url || unit.destinationUrl
                                   || unit.targetUrl || unit.href
                                   || payload.clickUrl || payload.url || '';
                            window.webkit.messageHandlers.onNativeAdClick.postMessage({
                                adUnit: unit,
                                url: url,
                                btaFeedId: payload.btaFeedId,
                                index: payload.index
                            });
                        },
                        onAdImpression: function(payload) {
                            window.webkit.messageHandlers.onAdImpression.postMessage({
                                adUnit: payload.adUnit,
                                btaFeedId: payload.btaFeedId,
                                index: payload.index
                            });
                        },
                        onArticleImpression: function(payload) {
                            window.webkit.messageHandlers.onArticleImpression.postMessage({
                                article: payload.article,
                                btaFeedId: payload.btaFeedId,
                                index: payload.index
                            });
                        }
                    });

                    window.webkit.messageHandlers.onFeedReady.postMessage(null);

                    function reportHeight() {
                        var h = document.documentElement.scrollHeight;
                        window.webkit.messageHandlers.onContentHeightChanged.postMessage(h);
                    }

                    if (window.ResizeObserver) {
                        new ResizeObserver(function() { reportHeight(); })
                            .observe(document.documentElement);
                    } else {
                        new MutationObserver(function() { reportHeight(); })
                            .observe(document.body, {
                                childList: true, subtree: true, attributes: true
                            });
                    }
                    reportHeight();
                });
            </script>
        </body>
        </html>
        """
    }

    // MARK: - Constants

    static let cdnBaseURL = "https://dev-cdn.adnz.co/"
}

// MARK: - WKNavigationDelegate

extension BtaFeedView: WKNavigationDelegate {

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // All taps are handled by the JS bridge; suppress unexpected link navigation.
        decisionHandler(navigationAction.navigationType == .linkActivated ? .cancel : .allow)
    }
}

// MARK: - UIView helper

extension UIView {
    /// Walks the responder chain to find the nearest enclosing `UIViewController`.
    func closestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController { return vc }
            responder = r.next
        }
        return nil
    }
}
