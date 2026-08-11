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
    .package(url: "https://github.com/audienzz/bta-audienzz-ios-sdk", from: "0.1.12"),
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
        btaFeedView.load(
            btaFeedId: "your-bta-feed-id",
            pageUrl: "https://your-site.com/the-article" // canonical URL of the hosting page
        )
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

                BtaFeedSwiftUI(btaFeedId: "your-bta-feed-id", pageUrl: "https://your-site.com/the-article")
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

## Refreshing content

If your app refreshes page content on navigation (including back navigation) and you want
fresh recommendations, call `reload()`. Unlike `load()`, it does **not** collapse the feed
height to 0 first — the current height is kept and adjusts smoothly once the new content is
measured, so there is no blank flash or layout jump.

```swift
btaFeedView.reload()   // replays the last load() parameters with fresh recommendations
```

> Note: the recommendation system currently serves fresh content on a **3-hour refresh
> interval**, so calling `reload()` more often than that may return the same items.

In SwiftUI, change the `.reloadToken(_:)` value to trigger the same in-place refresh:

```swift
BtaFeedSwiftUI(btaFeedId: "…", pageUrl: "…")
    .reloadToken(refreshCount)   // increment refreshCount to refresh in place
```

---

## Loading state

During the initial `load()`, the feed reserves a small height and shows a centered loading
spinner instead of appearing at zero height. Once content arrives it resizes to fit; if the
feed errors or returns nothing (or a timeout elapses), it collapses so there is no empty space.

To show **your own** placeholder instead, disable the built-in one with
`isLoadingHolderEnabled: false` and use the `btaFeedViewDidLoad` / `didFailWithError` delegate
callbacks to hide yours:

```swift
btaFeedView.load(
    btaFeedId: "your-bta-feed-id",
    pageUrl: "https://your-site.com/the-article",
    isLoadingHolderEnabled: false // SDK stays at 0 height until content arrives
)
// show your own placeholder now; hide it in btaFeedViewDidLoad(_:) / didFailWithError
```

In SwiftUI, add the `.isLoadingHolderEnabled(false)` modifier.

---

## Orientation changes

The feed height recalculates **automatically** when the view's width changes (e.g. device
rotation) — you don't need to call `load()` or `reload()`. Avoid calling `reload()` on rotation:
it re-fetches recommendations and briefly holds the previous height, which can look wrong on
the new orientation.

---

## Custom fonts

The feed renders inside a Shadow DOM. The SDK injects the font stylesheets at the **document
level**, where they register globally and apply inside the feed (this is what makes custom fonts
work on Android, whose WebView ignores shadow-scoped `@font-face`). The **standard AdConsole fonts
load by default**, so you don't need to change anything.

To use different fonts, pass your own `fontStyleUrls`; to disable injection, pass an empty array:

```swift
btaFeedView.load(
    btaFeedId: "your-bta-feed-id",
    pageUrl: "https://your-site.com/the-article",
    fontStyleUrls: [
        "https://cdn.adnz.co/business-click-fonts/YourFont/stylesheet.css"
    ]
    // or fontStyleUrls: [] to disable
)
```

In SwiftUI, add the `.fontStyleUrls([...])` modifier.

---

## BtaFeedView API reference

| Method / Property | Description |
|-------------------|-------------|
| `delegate: BtaFeedDelegate?` | Set or replace the event delegate |
| `load(btaFeedId:pageUrl:debug:mockRecommendations:isDarkMode:isLoadingHolderEnabled:fontStyleUrls:)` | Load the feed. Call from `viewWillAppear` |
| `reload()` | Refresh content in place without collapsing the height. Replays the last `load()` params |
| `destroy()` | Release resources. Call from `viewWillDisappear` |

---

## BtaFeedSwiftUI modifier reference

| Modifier | Type | Description |
|----------|------|-------------|
| `.debug(Bool)` | `Bool` | Enable feed debug logging. **Do not use in production** |
| `.mockRecommendations(Bool)` | `Bool` | Show mock content. **Do not use in production** |
| `.isDarkMode(Bool?)` | `Bool?` | `true` forces dark, `false` forces light, `nil` auto-detects from the system |
| `.reloadToken(AnyHashable?)` | `AnyHashable?` | Change to a new value to refresh content in place without collapsing the height |
| `.isLoadingHolderEnabled(Bool)` | `Bool` | Show the SDK's loading spinner (reserved height) on initial load; `false` to use your own placeholder |
| `.fontStyleUrls([String])` | `[String]` | Font stylesheet URLs injected at the document level so custom fonts render inside the feed (parity with Android). Defaults to the standard AdConsole fonts; pass `[]` to disable |
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
