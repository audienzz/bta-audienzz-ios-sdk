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
    private var feedLoadedFired = false

    /// When `true`, the next ``load(btaFeedId:debug:mockRecommendations:)`` call with the same
    /// feed ID is skipped. Set just before presenting ``BtaWebViewController`` so the
    /// `viewWillAppear → load()` cycle on return does not reload the feed.
    private var suppressNextLoad = false

    /// Stored so we can recover after a WKWebView content-process termination.
    private struct LoadParams {
        let btaFeedId: String
        let pageUrl: String
        let debug: Bool
        let mockRecommendations: Bool
        let isDarkMode: Bool?
        let isLoadingHolderEnabled: Bool
        let fontStyleUrls: [String]
    }
    private var lastLoadParams: LoadParams?

    /// While > 0, a ``reload()`` is in progress and the view height must not shrink below
    /// this value — it holds the pre-reload height so the feed doesn't collapse to ~0 while
    /// the new (blank-then-growing) content loads. Released once the new content grows back
    /// to this height, or by a timeout for a genuinely shorter feed.
    private var reloadHeightFloor: CGFloat = 0

    /// Max time the reload height floor is held before settling to the new height.
    private static let reloadFloorTimeout: TimeInterval = 1.5

    /// Single-flight latch for blank-feed recovery, so the process-termination handler and
    /// the blank-on-return branch can't both reload at once. Cleared once content returns.
    private var isRecovering = false

    /// While true (the ~1s window right after returning from an article), height updates may
    /// only GROW — never shrink. Prevents a transient under-reported height from clipping the
    /// (complete) feed as the WKWebView repaints on-screen.
    private var returnGrowGuardActive = false

    /// Centered spinner shown over the reserved height during the initial load.
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    /// True while the initial-load spinner is shown (height reserved, not 0).
    private var isLoading = false

    /// Bumped per load so a stale loading timeout can't collapse a newer load.
    private var loadGeneration = 0

    /// Last laid-out width, to detect orientation/size changes and re-measure the height.
    private var lastLaidOutWidth: CGFloat = 0

    /// Delays (seconds) at which the feed is re-measured after a width change settles.
    private static let resizeRemeasureDelays: [TimeInterval] = [0, 0.1, 0.3]

    /// Reserved height shown with a spinner during the initial load.
    private static let loadingHeight: CGFloat = 120

    /// Max time the loading spinner shows before collapsing if no content arrives.
    private static let loadingTimeout: TimeInterval = 10

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
    ///   - pageUrl: The canonical URL of the article/page hosting the feed.
    ///              Used by the feed widget for contextual recommendations.
    ///   - debug: Enable feed debug logging (**do not use in production**).
    ///   - mockRecommendations: Show mock recommendations (**do not use in production**).
    ///   - isDarkMode: Override the color scheme: `true` forces dark theme, `false` forces
    ///     light theme, `nil` (default) auto-detects from the system via `prefers-color-scheme`.
    ///   - isLoadingHolderEnabled: When `true` (default), the SDK reserves height and shows a
    ///     loading spinner during the initial load. Set `false` to suppress it and show your
    ///     own loading placeholder instead (the feed stays at 0 height until content arrives).
    ///   - fontStyleUrls: Font stylesheet URLs (containing `@font-face` rules) injected at the
    ///     document level so the fonts are usable inside the feed's Shadow DOM. Defaults to the
    ///     standard AdConsole fonts (``defaultFontStyleUrls``); pass your own URLs to override, or
    ///     an empty array to disable.
    public func load(
        btaFeedId: String,
        pageUrl: String,
        debug: Bool = false,
        mockRecommendations: Bool = false,
        isDarkMode: Bool? = nil,
        isLoadingHolderEnabled: Bool = true,
        fontStyleUrls: [String] = BtaFeedView.defaultFontStyleUrls
    ) {
        // Suppress reload when returning from the ad/article WebView for the same feed.
        // Still re-attach bridge handlers — destroy() may have removed them when the
        // fullscreen modal caused viewWillDisappear to fire on the parent view controller.
        if suppressNextLoad && btaFeedId == currentFeedId {
            suppressNextLoad = false
            rebuildBridge(btaFeedId: btaFeedId)
            // The WKWebView content is preserved and was already correctly sized before we left.
            // While it repaints coming back on-screen it can transiently under-report its height,
            // which would clip the (complete) feed and get worse over the settle passes — so guard
            // the return window to GROW-ONLY: re-measure to catch any growth, but never shrink.
            beginReturnGrowGuard()
            remeasureAfterReturn(attempt: 0)
            return
        }
        suppressNextLoad = false
        isRecovering = false // a fresh, user-initiated load supersedes any recovery
        returnGrowGuardActive = false // ...and supersedes the return grow-guard
        performLoad(
            LoadParams(btaFeedId: btaFeedId, pageUrl: pageUrl, debug: debug, mockRecommendations: mockRecommendations, isDarkMode: isDarkMode, isLoadingHolderEnabled: isLoadingHolderEnabled, fontStyleUrls: fontStyleUrls),
            resetHeight: true
        )
    }

    /// Reload the feed content in place — fetches fresh recommendations without first
    /// collapsing the view height to 0, so there is no blank flash or layout jump. The
    /// pre-reload height is held while the new content loads and only settles to the new
    /// size once it has rendered, so the feed does not visibly jump.
    ///
    /// Use this when your app refreshes page content (e.g. on back navigation) and you
    /// want new recommendations without the initial-load height reset. Replays the most
    /// recent ``load(btaFeedId:pageUrl:debug:mockRecommendations:isDarkMode:)`` parameters;
    /// no-op if `load` has never been called.
    public func reload() {
        guard let params = lastLoadParams else { return }
        // Skip the suppress-on-return flag — this is an explicit content refresh.
        suppressNextLoad = false
        // Hold the current height so the feed doesn't collapse while the new content
        // loads (the fresh page reports a near-zero height before the feed renders).
        reloadHeightFloor = heightConstraint.constant
        performLoad(params, resetHeight: false)
        // Safety net: release the floor after a max wait so a genuinely shorter feed
        // settles to its true (smaller) height even if it never reaches the old one.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reloadFloorTimeout) { [weak self] in
            self?.releaseReloadFloor()
        }
    }

    /// Drop the reload height floor and settle to the new content's true height.
    private func releaseReloadFloor() {
        guard reloadHeightFloor > 0 else { return }
        reloadHeightFloor = 0
        webView.evaluateJavaScript(Self.robustHeightJS) { [weak self] result, _ in
            guard let self else { return }
            let height: CGFloat
            if let d = result as? Double { height = CGFloat(d) }
            else if let n = result as? NSNumber { height = CGFloat(n.doubleValue) }
            else { return }
            if height > 0 { self.updateHeight(height) }
        }
    }

    /// Height query used everywhere the SDK measures the feed. Uses the BODY content height,
    /// not `documentElement`, whose scrollHeight is clamped to the viewport/frame height and so
    /// can never report shorter than the current frame — which leaves a huge gap after the feed
    /// shrinks (e.g. rotating to a shorter landscape layout) and can also clip it.
    private static let robustHeightJS =
        "document.body ? Math.max(document.body.scrollHeight, document.body.offsetHeight) : 0"

    /// Delays (seconds) at which the feed is re-measured after returning from an article,
    /// so a stale or still-settling layout is corrected rather than left clipped.
    private static let returnRemeasureDelays: [TimeInterval] = [0, 0.15, 0.4, 0.8]

    /// How long height updates stay grow-only after returning from an article (covers the
    /// re-measure passes above plus a small buffer).
    private static let returnGrowGuardDuration: TimeInterval = 1.2

    /// Re-measure the feed after returning from the fullscreen article, across several settling
    /// passes, so a stale or clipped height is corrected. Does NOT reload on an early zero reading
    /// — the WKWebView often reports a transient 0 height while it repaints on returning on-screen,
    /// and reloading then would cause an unnecessary "new load"/jump. Only if the feed is *still*
    /// blank after every settle pass do we treat it as a discarded process and reload in place.
    private func remeasureAfterReturn(attempt: Int) {
        webView.evaluateJavaScript(Self.robustHeightJS) { [weak self] result, _ in
            guard let self else { return }
            var height: CGFloat = 0
            if let d = result as? Double { height = CGFloat(d) }
            else if let n = result as? NSNumber { height = CGFloat(n.doubleValue) }

            if height > 0 {
                self.updateHeight(height)
            }

            let next = attempt + 1
            if next < Self.returnRemeasureDelays.count {
                // Keep re-measuring — a transient 0 now may become the real height shortly.
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.returnRemeasureDelays[next]) { [weak self] in
                    self?.remeasureAfterReturn(attempt: next)
                }
            } else if height <= 0 {
                // Still blank after the final settle pass → the content process was almost
                // certainly discarded. Reload once, holding the height so it doesn't collapse.
                guard !self.isRecovering, let params = self.lastLoadParams else { return }
                self.isRecovering = true
                self.reloadHeightFloor = self.heightConstraint.constant
                self.performLoad(params, resetHeight: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.reloadFloorTimeout) { [weak self] in
                    self?.releaseReloadFloor()
                }
            }
        }
    }

    private func performLoad(_ params: LoadParams, resetHeight: Bool) {
        currentFeedId = params.btaFeedId
        lastLoadParams = params
        viewableImpressionFired = false
        feedLoadedFired = false
        // On a full load, show the loading state (reserved height + spinner) instead of
        // collapsing to 0 — unless the publisher opted out to show their own placeholder;
        // on a reload the floor (set by reload()) keeps the current height.
        if resetHeight {
            reloadHeightFloor = 0
            if params.isLoadingHolderEnabled {
                setLoading(true)
            } else {
                updateHeight(0)
            }
        }

        BtaEventTracker.shared.track(BtaEvent(type: .pageView, btaFeedId: params.btaFeedId))

        startViewabilityTimer()
        rebuildBridge(btaFeedId: params.btaFeedId)

        let html = buildHTML(
            feedId: params.btaFeedId,
            pageUrl: params.pageUrl,
            debug: params.debug,
            mockRecommendations: params.mockRecommendations,
            isDarkMode: params.isDarkMode,
            fontStyleUrls: params.fontStyleUrls
        )
        webView.loadHTMLString(html, baseURL: URL(string: Self.cdnBaseURL))
    }

    /// Release resources. Call from `viewWillDisappear` or the owning object's `deinit`.
    public func destroy() {
        stopViewabilityTimer()
        // When navigating to an article, suppress in-progress resource loads being cancelled —
        // the WebView should keep its content intact so returning looks seamless.
        if !suppressNextLoad {
            webView.stopLoading()
        }
        removeBridgeHandlers()
        bridge = nil
    }

    // MARK: - Intrinsic content size

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: heightConstraint.constant)
    }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        guard width > 0 else { return }
        if lastLaidOutWidth == 0 {
            // First layout — the load flow measures the initial height; just record the width.
            lastLaidOutWidth = width
            return
        }
        guard width != lastLaidOutWidth else { return }
        // Width changed (e.g. orientation change): the content reflows to the new width, so
        // its height changes. Re-measure and apply it — no reload() needed by the publisher.
        lastLaidOutWidth = width
        remeasureAfterResize(attempt: 0)
    }

    /// Re-measure the feed after a width change settles and apply the true height (which may
    /// grow or shrink). Unlike the return path, this never reloads and never holds a floor —
    /// on rotation we want to follow the real new height in both directions.
    private func remeasureAfterResize(attempt: Int) {
        guard currentFeedId != nil, !isLoading else { return }
        webView.evaluateJavaScript(Self.robustHeightJS) { [weak self] result, _ in
            guard let self else { return }
            var height: CGFloat = 0
            if let d = result as? Double { height = CGFloat(d) }
            else if let n = result as? NSNumber { height = CGFloat(n.doubleValue) }
            if height > 0 { self.updateHeight(height) }
            let next = attempt + 1
            if next < Self.resizeRemeasureDelays.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.resizeRemeasureDelays[next]) { [weak self] in
                    self?.remeasureAfterResize(attempt: next)
                }
            }
        }
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

        // Centered loading spinner, shown over the reserved height during the initial load.
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    /// Toggle the initial-load loading state. When enabled, reserves ``loadingHeight`` and
    /// shows a centered spinner instead of collapsing to 0; a timeout collapses it if content
    /// never arrives, so there is no permanent dead space.
    private func setLoading(_ loading: Bool) {
        isLoading = loading
        if loading {
            loadingIndicator.startAnimating()
            updateHeight(Self.loadingHeight)
            loadGeneration += 1
            let generation = loadGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.loadingTimeout) { [weak self] in
                guard let self, self.isLoading, generation == self.loadGeneration else { return }
                self.setLoading(false)
                self.updateHeight(0)
            }
        } else {
            loadingIndicator.stopAnimating()
        }
    }

    // MARK: - Bridge management

    private func rebuildBridge(btaFeedId: String) {
        removeBridgeHandlers()

        let newBridge = BtaJsBridge(btaFeedId: btaFeedId, delegate: delegate, feedView: self)

        newBridge.onHeightChanged = { [weak self] height in
            guard let self else { return }
            // While the loading state is shown, ignore empty-height reports (the page reports
            // ~0 until the feed renders); switch to real content on the first non-zero height.
            if self.isLoading {
                if height <= 0 { return }
                self.setLoading(false)
            }
            if self.reloadHeightFloor > 0 {
                // Mid-reload: never shrink below the pre-reload height. Once the new
                // content grows back to it, following the true height is safe again.
                self.updateHeight(max(height, self.reloadHeightFloor))
                if height >= self.reloadHeightFloor { self.reloadHeightFloor = 0 }
            } else {
                self.updateHeight(height)
            }
            // Content is back — any in-flight blank-feed recovery is done.
            if height > 0 { self.isRecovering = false }
            // Fire didLoad the first time real content appears (height > 0).
            if height > 0 && !self.feedLoadedFired {
                self.feedLoadedFired = true
                self.delegate?.btaFeedViewDidLoad(self)
            }
            if !self.viewableImpressionFired {
                self.checkViewabilityAndTrack()
            }
        }
        newBridge.onFeedLoaded = { /* JS SDK initialised — btaFeedViewDidLoad fires on first non-zero height */ }
        newBridge.onFeedError = { [weak self] error in
            guard let self else { return }
            // No content will render — clear the loading state and collapse.
            if self.isLoading {
                self.setLoading(false)
                self.updateHeight(0)
            }
            self.delegate?.btaFeedView(self, didFailWithError: error)
        }
        newBridge.onWillNavigateAway = { [weak self] in
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

    /// Enable grow-only height updates for a short window after returning from an article,
    /// so a transient under-reported height can't clip the complete feed.
    private func beginReturnGrowGuard() {
        returnGrowGuardActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.returnGrowGuardDuration) { [weak self] in
            self?.returnGrowGuardActive = false
        }
    }

    private func updateHeight(_ height: CGFloat) {
        // Just after returning from an article the feed is already correctly sized; ignore any
        // shrink (a transient under-report) so the complete feed can't be clipped. Growth is fine.
        if returnGrowGuardActive && height < heightConstraint.constant { return }
        guard heightConstraint.constant != height else { return }
        heightConstraint.constant = height
        invalidateIntrinsicContentSize()
        // Apply immediately (no animation). The feed re-measures many times as items and
        // images render, so animating each change makes it visibly grow/bounce up from the
        // bottom on first load; snapping to content height reads as normal top-down filling.
        delegate?.btaFeedView(self, didUpdateHeight: height)
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

    private func buildHTML(feedId: String, pageUrl: String, debug: Bool, mockRecommendations: Bool, isDarkMode: Bool?, fontStyleUrls: [String]) -> String {
        let debugLine = debug ? "debug: true," : ""
        let mockLine  = mockRecommendations ? "mockRecommendations: true," : ""
        let darkLine: String
        switch isDarkMode {
        case .some(true):  darkLine = "forceDarkTheme: true,"
        case .some(false): darkLine = ""
        case .none:        darkLine = "isDarkThemeSupported: true,"
        }

        // Inject the publisher's font stylesheets at the DOCUMENT level, so their @font-face
        // rules are registered globally and are usable inside the feed's Shadow DOM. Android's
        // (older) WebView ignores @font-face declared inside a shadow root, so a document-level
        // <link> is what makes the custom fonts render there.
        let fontLinks = fontStyleUrls
            .map { "<link rel=\"stylesheet\" href=\"\(Self.htmlAttributeEscaped($0))\" />" }
            .joined(separator: "\n            ")

        // NOTE: On iOS, WKWebView JS height is already in UIKit points (no scale factor needed).
        // NOTE: Uses plain function() syntax and var for broad WebView compatibility.
        return """
        <!doctype html>
        <html lang="en">
        <head>
            <base target="_parent" />
            <meta charset="UTF-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0" />
            \(fontLinks)
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body { overflow: hidden; width: 100%; }
            </style>
        </head>
        <body>
            <script type="text/javascript">
                window.adnzBtaFeed = window.adnzBtaFeed || {};
                window.adnzBtaFeed.queue = window.adnzBtaFeed.queue || [];
                window.adnzBtaFeed.queue.push(function() {
                    try {
                        window.adnzBtaFeed.start({
                            btaFeedId: '\(feedId)',
                            url: '\(pageUrl)',
                            webview: true,
                            \(debugLine)
                            \(mockLine)
                            \(darkLine)
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
                            },
                            onError: function(error) {
                                var msg = error && error.message ? error.message
                                        : (typeof error === 'string' ? error : 'Feed error');
                                window.webkit.messageHandlers.onFeedError.postMessage(msg);
                            }
                        });
                    } catch (e) {
                        window.webkit.messageHandlers.onFeedError.postMessage(
                            'Failed to start feed: ' + (e && e.message ? e.message : String(e))
                        );
                        return;
                    }

                    // Measure the BODY content height (not documentElement, whose scrollHeight is
                    // clamped to the viewport/frame and so can't shrink — leaving a huge gap after
                    // the feed gets shorter, e.g. rotating to landscape).
                    function reportHeight() {
                        var body = document.body;
                        var h = body ? Math.max(body.scrollHeight, body.offsetHeight) : 0;
                        window.webkit.messageHandlers.onContentHeightChanged.postMessage(h);
                    }

                    if (window.ResizeObserver) {
                        var ro = new ResizeObserver(function() { reportHeight(); });
                        ro.observe(document.documentElement);
                        if (document.body) ro.observe(document.body);
                    } else {
                        new MutationObserver(function() { reportHeight(); })
                            .observe(document.body, {
                                childList: true, subtree: true, attributes: true
                            });
                    }
                    // Re-measure once every image has decoded — recommendation teasers are
                    // added dynamically, so their loads can expand the layout after first paint.
                    window.addEventListener('load', function() { reportHeight(); });
                    document.addEventListener('load', function(e) {
                        if (e.target && e.target.tagName === 'IMG') reportHeight();
                    }, true);
                    reportHeight();
                });
            </script>
            <script async src="\(Self.cdnBaseURL)bta-feed/index.js"
                onerror="window.webkit.messageHandlers.onFeedError.postMessage('Failed to load BTA feed script')"></script>
        </body>
        </html>
        """
    }

    // MARK: - Constants

    static let cdnBaseURL = "https://cdn.adnz.co/"

    /// Font stylesheets injected at the document level by default so the standard AdConsole fonts
    /// render inside the feed's Shadow DOM (parity with Android). Override via `load`'s
    /// `fontStyleUrls`, or pass an empty array to disable.
    public static let defaultFontStyleUrls = [
        "\(cdnBaseURL)business-click-fonts/Knockout/stylesheet.css",
        "\(cdnBaseURL)business-click-fonts/Tiempos/stylesheet.css",
    ]

    /// Escape a string for safe use inside a double-quoted HTML attribute.
    private static func htmlAttributeEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
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

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // iOS killed the WebContent process (memory pressure). Reload the feed transparently.
        guard let params = lastLoadParams, !isRecovering else { return }
        isRecovering = true
        suppressNextLoad = false
        performLoad(params, resetHeight: true)
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
