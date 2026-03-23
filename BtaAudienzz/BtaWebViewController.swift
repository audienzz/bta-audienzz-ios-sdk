import UIKit
import WebKit

/// Full-screen WebView presented when an ad is clicked and the delegate returns `false`.
public final class BtaWebViewController: UIViewController {

    // MARK: - Private

    private let targetURL: URL
    private var webView: WKWebView!

    // MARK: - Init

    public init(url: URL) {
        self.targetURL = url
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupWebView()
        setupNavigationBar()
        webView.load(URLRequest(url: targetURL))
    }

    // MARK: - Setup

    private func setupWebView() {
        webView = WKWebView(frame: .zero)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "safari"),
            style: .plain,
            target: self,
            action: #selector(openInSafari)
        )
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func openInSafari() {
        UIApplication.shared.open(targetURL)
    }
}

// MARK: - WKNavigationDelegate

extension BtaWebViewController: WKNavigationDelegate {

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Mirror the page title in the navigation bar.
        if let title = webView.title, !title.isEmpty {
            self.title = title
        }
    }
}
