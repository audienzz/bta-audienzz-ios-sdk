import SwiftUI

/// SwiftUI wrapper for ``BtaFeedView``.
///
/// Uses a modifier-style API consistent with SwiftUI conventions.
///
/// ## Basic usage
///
/// ```swift
/// // AppDelegate — once
/// BtaSdk.initialize(publisherId: "your-publisher-id")
///
/// // Inside any View
/// BtaFeedSwiftUI(btaFeedId: "your-bta-feed-id")
///     .frame(maxWidth: .infinity)
///     .debug(true)
///     .mockRecommendations(true)
///     .onArticleClick { payload in
///         false // SDK opens fullscreen WebView
///     }
///     .onAdClick { _ in
///         false // SDK opens fullscreen WebView
///     }
/// ```
@available(iOS 14.0, *)
public struct BtaFeedSwiftUI: UIViewRepresentable {

    // MARK: - Properties

    let btaFeedId: String
    let pageUrl: String
    var debug: Bool = false
    var mockRecommendations: Bool = false
    var isDarkMode: Bool? = nil
    var reloadToken: AnyHashable? = nil
    var isLoadingHolderEnabled: Bool = true
    var fontStyleUrls: [String] = BtaFeedView.defaultFontStyleUrls
    var onArticleClick: ((ArticleClickPayload) -> Bool)?
    var onAdClick: ((AdClickPayload) -> Bool)?
    var onFeedLoaded: (() -> Void)?
    var onFeedError: ((String) -> Void)?
    var onHeightChanged: ((CGFloat) -> Void)?

    // MARK: - Init

    public init(btaFeedId: String, pageUrl: String) {
        self.btaFeedId = btaFeedId
        self.pageUrl = pageUrl
    }

    // MARK: - UIViewRepresentable

    public func makeUIView(context: Context) -> BtaFeedView {
        BtaFeedView()
    }

    public func updateUIView(_ uiView: BtaFeedView, context: Context) {
        uiView.delegate = context.coordinator
        context.coordinator.parent = self

        // Reload when the feed ID or page URL changes, but not on every SwiftUI
        // state change (which would cause constant reloads).
        if context.coordinator.lastLoadedFeedId != btaFeedId
            || context.coordinator.lastLoadedPageUrl != pageUrl {
            context.coordinator.lastLoadedFeedId = btaFeedId
            context.coordinator.lastLoadedPageUrl = pageUrl
            context.coordinator.lastReloadToken = reloadToken
            context.coordinator.didCaptureInitialToken = true
            uiView.load(
                btaFeedId: btaFeedId,
                pageUrl: pageUrl,
                debug: debug,
                mockRecommendations: mockRecommendations,
                isDarkMode: isDarkMode,
                isLoadingHolderEnabled: isLoadingHolderEnabled,
                fontStyleUrls: fontStyleUrls
            )
            return
        }

        // Refresh the content in place when reloadToken changes (after the initial load),
        // keeping the current height so there is no blank flash or jump.
        if !context.coordinator.didCaptureInitialToken {
            context.coordinator.didCaptureInitialToken = true
            context.coordinator.lastReloadToken = reloadToken
        } else if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            uiView.reload()
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public static func dismantleUIView(_ uiView: BtaFeedView, coordinator: Coordinator) {
        uiView.destroy()
    }

    // MARK: - Coordinator

    public final class Coordinator: NSObject, BtaFeedDelegate {

        var parent: BtaFeedSwiftUI
        var lastLoadedFeedId: String?
        var lastLoadedPageUrl: String?
        var lastReloadToken: AnyHashable?
        var didCaptureInitialToken = false

        init(_ parent: BtaFeedSwiftUI) {
            self.parent = parent
        }

        public func btaFeedView(_ view: BtaFeedView, didClickArticle payload: ArticleClickPayload) -> Bool {
            parent.onArticleClick?(payload) ?? false
        }

        public func btaFeedView(_ view: BtaFeedView, didClickAd payload: AdClickPayload) -> Bool {
            parent.onAdClick?(payload) ?? false
        }

        public func btaFeedViewDidLoad(_ view: BtaFeedView) {
            parent.onFeedLoaded?()
        }

        public func btaFeedView(_ view: BtaFeedView, didFailWithError error: String) {
            parent.onFeedError?(error)
        }

        public func btaFeedView(_ view: BtaFeedView, didUpdateHeight height: CGFloat) {
            parent.onHeightChanged?(height)
        }
    }
}

// MARK: - Modifier-style API

@available(iOS 14.0, *)
public extension BtaFeedSwiftUI {

    func debug(_ enabled: Bool) -> Self {
        var copy = self; copy.debug = enabled; return copy
    }

    func mockRecommendations(_ enabled: Bool) -> Self {
        var copy = self; copy.mockRecommendations = enabled; return copy
    }

    func isDarkMode(_ value: Bool?) -> Self {
        var copy = self; copy.isDarkMode = value; return copy
    }

    /// Change this to any new value to refresh the feed content in place (fresh
    /// recommendations) without collapsing the feed height — no blank flash or jump.
    /// Leave unchanged to avoid reloading.
    func reloadToken(_ value: AnyHashable?) -> Self {
        var copy = self; copy.reloadToken = value; return copy
    }

    /// When `true` (default), the SDK shows a loading spinner with reserved height during
    /// the initial load. Set `false` to show your own placeholder instead.
    func isLoadingHolderEnabled(_ enabled: Bool) -> Self {
        var copy = self; copy.isLoadingHolderEnabled = enabled; return copy
    }

    /// Font stylesheet URLs (with `@font-face` rules) injected at the document level so the
    /// fonts are usable inside the feed's Shadow DOM (needed for custom fonts on Android).
    func fontStyleUrls(_ urls: [String]) -> Self {
        var copy = self; copy.fontStyleUrls = urls; return copy
    }

    func onArticleClick(_ action: @escaping (ArticleClickPayload) -> Bool) -> Self {
        var copy = self; copy.onArticleClick = action; return copy
    }

    func onAdClick(_ action: @escaping (AdClickPayload) -> Bool) -> Self {
        var copy = self; copy.onAdClick = action; return copy
    }

    func onFeedLoaded(_ action: @escaping () -> Void) -> Self {
        var copy = self; copy.onFeedLoaded = action; return copy
    }

    func onFeedError(_ action: @escaping (String) -> Void) -> Self {
        var copy = self; copy.onFeedError = action; return copy
    }

    func onHeightChanged(_ action: @escaping (CGFloat) -> Void) -> Self {
        var copy = self; copy.onHeightChanged = action; return copy
    }
}
