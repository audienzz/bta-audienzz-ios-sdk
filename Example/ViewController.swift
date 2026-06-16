import UIKit
import BtaAudienzz

final class ViewController: UIViewController {

    private static let btaFeedId = "5b0a5694-de8d-4ddb-8bd4-a871bb55f09b"

    /** Replace with the canonical URL of the article page hosting this feed. */
    private static let pageUrl = "https://www.example.com/article/sample-article"

    // MARK: - Views

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let articleLabel = UILabel()
    private let btaFeedView = BtaFeedView()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "BTA Feed (UIKit)"
        view.backgroundColor = .systemBackground
        setupLayout()
        btaFeedView.delegate = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        print("[Example] load() called — waiting for content...")
        btaFeedView.load(btaFeedId: Self.btaFeedId, pageUrl: Self.pageUrl, debug: true, mockRecommendations: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        btaFeedView.destroy()
    }

    // MARK: - Layout

    private func setupLayout() {
        articleLabel.text = "This is a sample article.\n\nThe BTA feed renders below once the SDK has loaded the widget from the CDN."
        articleLabel.font = .preferredFont(forTextStyle: .body)
        articleLabel.numberOfLines = 0

        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.addArrangedSubview(articleLabel)
        contentStack.addArrangedSubview(btaFeedView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32),
        ])
    }
}

// MARK: - BtaFeedDelegate

extension ViewController: BtaFeedDelegate {

    func btaFeedView(_ view: BtaFeedView, didClickArticle payload: ArticleClickPayload) -> Bool {
        print("[Example] Article clicked: index=\(payload.index) url=\(payload.url)")
        return false // Let SDK open in fullscreen WebView
    }

    func btaFeedView(_ view: BtaFeedView, didClickAd payload: AdClickPayload) -> Bool {
        print("[Example] Ad clicked: index=\(payload.index) url=\(payload.url)")
        return false
    }

    func btaFeedViewDidLoad(_ view: BtaFeedView) {
        print("[Example] btaFeedViewDidLoad — content rendered (first non-zero height received)")
    }

    func btaFeedView(_ view: BtaFeedView, didFailWithError error: String) {
        print("[Example] didFailWithError — \(error)")
    }

    func btaFeedView(_ view: BtaFeedView, didUpdateHeight height: CGFloat) {
        print("[Example] didUpdateHeight — \(height)pt")
    }
}
