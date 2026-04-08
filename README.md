# BTA Audienzz iOS SDK

Below The Article (BTA) feed SDK for iOS. Embeds the Audienzz BTA recommendation and ad feed in any iOS screen — available as a `UIView` subclass for UIKit and as a SwiftUI view for iOS 14+.

---

## Requirements

- iOS 13+
- Swift 5.7+
- No external dependencies — uses only system frameworks (UIKit, WebKit, Foundation)

---

## Installation

### Swift Package Manager

Add the package to your project in Xcode:

**File → Add Packages…** → enter the repository URL → select **BtaAudienzz**.

Or add it to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/audienzz/bta-audienzz-ios", from: "1.0.0"),
],
targets: [
    .target(name: "YourTarget", dependencies: ["BtaAudienzz"]),
]
```

### CocoaPods

```ruby
pod 'BtaAudienzz'
```

---

## Setup

### 1. Initialize the SDK

Call `BtaSdk.initialize(publisherId:)` once, before any feed view is created — typically in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`:

```swift
import BtaAudienzz

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        BtaSdk.initialize(publisherId: "your-publisher-id")
        return true
    }
}
```

---

## Usage — UIKit

### 2. Add the view

Add `BtaFeedView` to your view hierarchy — programmatically or in Interface Builder:

```swift
import BtaAudienzz

class ArticleViewController: UIViewController {

    private let btaFeedView = BtaFeedView()

    override func viewDidLoad() {
        super.viewDidLoad()

        btaFeedView.delegate = self
        btaFeedView.translatesAutoresizingMaskIntoConstraints = false

        // Embed inside a UIScrollView for full scrollability.
        scrollView.addSubview(btaFeedView)
        NSLayoutConstraint.activate([
            btaFeedView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            btaFeedView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            btaFeedView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            // Top anchor pinned below your article content.
            btaFeedView.topAnchor.constraint(equalTo: articleLabel.bottomAnchor, constant: 16),
            btaFeedView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        btaFeedView.load(btaFeedId: "your-bta-feed-id")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        btaFeedView.destroy()
    }
}
```

### 3. Implement the delegate

```swift
extension ArticleViewController: BtaFeedDelegate {

    // Return false  → SDK opens the URL in a fullscreen in-app browser.
    // Return true   → you handle navigation yourself; SDK opens nothing.
    func btaFeedView(_ view: BtaFeedView, didClickArticle payload: ArticleClickPayload) -> Bool {
        return false
    }

    func btaFeedView(_ view: BtaFeedView, didClickAd payload: AdClickPayload) -> Bool {
        return false
    }

    func btaFeedViewDidLoad(_ view: BtaFeedView) {
        // Feed widget initialised (recommendations may still be loading).
    }

    func btaFeedView(_ view: BtaFeedView, didFailWithError error: String) {
        print("BtaFeed error: \(error)")
    }
}
```

---

## Usage — SwiftUI (iOS 14+)

No lifecycle wiring required — the view handles it automatically.

```swift
import BtaAudienzz
import SwiftUI

struct ArticleView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {

                // Your article content here...

                BtaFeedSwiftUI(btaFeedId: "your-bta-feed-id")
                    .onArticleClick { payload in
                        false  // false → SDK opens fullscreen browser
                    }
                    .onAdClick { payload in
                        false
                    }
                    .onFeedLoaded {
                        // Feed initialised
                    }
                    .onFeedError { error in
                        print("BtaFeed error: \(error)")
                    }
                    .frame(maxWidth: .infinity)  // .frame() must come after SDK modifiers
            }
        }
    }
}
```

> **Important:** Place `.frame()` and other standard SwiftUI modifiers **after** all `BtaFeedSwiftUI`-specific modifiers (`.onArticleClick`, `.onAdClick`, etc.), otherwise the type system will lose access to the custom modifiers.

---

## Click handling

By default, clicking an article or ad opens the destination URL in a fullscreen in-app browser (`BtaWebViewController`) with a close button (✕) in the top-left corner and a Safari button in the top-right corner. No external browser is opened.

To handle navigation yourself, return `true` from the click callback:

```swift
func btaFeedView(_ view: BtaFeedView, didClickArticle payload: ArticleClickPayload) -> Bool {
    // Open in your own flow, push a detail VC, etc.
    navigationController?.pushViewController(
        ArticleDetailViewController(url: payload.url),
        animated: true
    )
    return true  // SDK won't open anything
}
```

### Click payload fields

**`ArticleClickPayload`**

| Field | Type | Description |
|-------|------|-------------|
| `btaFeedId` | `String` | Feed ID that triggered the click |
| `index` | `Int` | Zero-based position of the item in the feed |
| `url` | `String` | Destination URL |
| `title` | `String` | Article title |
| `article` | `[String: Any]` | Full raw article object from the feed |

**`AdClickPayload`**

| Field | Type | Description |
|-------|------|-------------|
| `btaFeedId` | `String` | Feed ID that triggered the click |
| `index` | `Int` | Zero-based position of the item in the feed |
| `url` | `String` | Destination URL |
| `adUnit` | `[String: Any]` | Full raw ad unit object from the feed |

---

## BtaFeedView API reference

| Method / Property | Description |
|-------------------|-------------|
| `delegate: BtaFeedDelegate?` | Set or replace the event delegate |
| `load(btaFeedId:debug:mockRecommendations:)` | Load the feed. Call from `viewWillAppear` |
| `destroy()` | Release resources. Call from `viewWillDisappear` |

---

## BtaFeedSwiftUI modifier reference

| Modifier | Type | Description |
|----------|------|-------------|
| `.debug(Bool)` | `Bool` | Enable feed debug logging. **Do not use in production** |
| `.mockRecommendations(Bool)` | `Bool` | Show mock content. **Do not use in production** |
| `.onArticleClick { ArticleClickPayload -> Bool }` | closure | Return `false` for SDK default, `true` to handle yourself |
| `.onAdClick { AdClickPayload -> Bool }` | closure | Return `false` for SDK default, `true` to handle yourself |
| `.onFeedLoaded { }` | closure | Called when the feed widget initialises |
| `.onFeedError { String }` | closure | Called on feed initialisation error |

---

## Analytics

The SDK automatically tracks the following events and sends them to the Audienzz analytics pipeline. No integration work is required.

| Event | Trigger |
|-------|---------|
| `btafeed.pageview` | Every `load()` call |
| `btafeed.viewable_impression` | Feed is ≥50% visible on screen |
| `btafeed.article_impression` | Article unit enters the viewport |
| `btafeed.article_click` | Article clicked |
| `btafeed.ad_impression` | Ad unit enters the viewport |
| `btafeed.ad_click` | Ad clicked |

Events are batched with a 2-second debounce and sent in [CloudEvents 1.0](https://cloudevents.io) format. A stable visitor ID is persisted in `UserDefaults` across sessions; a new session ID is generated per app launch.

---

## Debugging

Pass `debug: true` and `mockRecommendations: true` to `load()` (or the corresponding SwiftUI modifiers) to show mock content without a live feed configuration:

```swift
// UIKit
btaFeedView.load(
    btaFeedId: "your-bta-feed-id",
    debug: true,
    mockRecommendations: true
)

// SwiftUI
BtaFeedSwiftUI(btaFeedId: "your-bta-feed-id")
    .debug(true)
    .mockRecommendations(true)
```

To inspect the feed in Safari Web Inspector, enable WebView debugging in your scheme's `Run` action or at launch:

```swift
// AppDelegate, debug builds only
if #available(iOS 16.4, *) {
    // Enabled automatically via scheme setting in Xcode 14.3+
}
```
