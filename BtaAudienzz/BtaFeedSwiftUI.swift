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
    var debug: Bool = false
    var mockRecommendations: Bool = false
    var onArticleClick: ((ArticleClickPayload) -> Bool)?
    var onAdClick: ((AdClickPayload) -> Bool)?
    var onFeedLoaded: (() -> Void)?
    var onFeedError: ((String) -> Void)?

    // MARK: - Init

    public init(btaFeedId: String) {
        self.btaFeedId = btaFeedId
    }

    // MARK: - UIViewRepresentable

    public func makeUIView(context: Context) -> BtaFeedView {
        BtaFeedView()
    }

    public func updateUIView(_ uiView: BtaFeedView, context: Context) {
        uiView.delegate = context.coordinator
        context.coordinator.parent = self

        // Load only when the feed ID changes or on first appearance — not on every
        // SwiftUI state change (which would cause constant reloads).
        if context.coordinator.lastLoadedFeedId != btaFeedId {
            context.coordinator.lastLoadedFeedId = btaFeedId
            uiView.load(
                btaFeedId: btaFeedId,
                debug: debug,
                mockRecommendations: mockRecommendations
            )
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
}
