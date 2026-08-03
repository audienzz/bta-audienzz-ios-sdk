import SwiftUI
import BtaAudienzz

/// SwiftUI example — mirrors the Android app's BtaComposeActivity.
@available(iOS 14.0, *)
struct SwiftUIExampleView: View {

    private static let btaFeedId = "92692c82-cb38-4164-b77c-e89d56cb486d"

    /** Replace with the canonical URL of the article page hosting this feed. */
    private static let pageUrl = "https://www.example.com/article/sample-article"

    // Change this token to refresh the feed in place (no height jump). The floating
    // button below increments it, mirroring `btaFeedView.reload()` on the UIKit API.
    @State private var reloadToken = 0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 0) {
                    Text("""
                        This is a sample article.\n\n\
                        The BTA (Below The Article) feed renders below once the \
                        SDK has loaded the widget.
                        """)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)

                    BtaFeedSwiftUI(btaFeedId: Self.btaFeedId, pageUrl: Self.pageUrl)
                        .debug(true)
                        .mockRecommendations(true)
                        .reloadToken(reloadToken)
                        .onArticleClick { payload in
                            print("[SwiftUI] Article clicked: index=\(payload.index) url=\(payload.url)")
                            return false // SDK opens BtaWebViewController
                        }
                        .onAdClick { payload in
                            print("[SwiftUI] Ad clicked: index=\(payload.index) url=\(payload.url)")
                            return false // SDK opens BtaWebViewController
                        }
                        .onFeedLoaded {
                            print("[SwiftUI] BTA feed loaded successfully")
                        }
                        .onFeedError { error in
                            print("[SwiftUI] BTA feed error: \(error)")
                        }
                        .onHeightChanged { height in
                            print("[SwiftUI] BTA feed height updated: \(height)pt")
                        }
                        .frame(maxWidth: .infinity) // SwiftUI modifiers go after all BtaFeedSwiftUI modifiers
                }
            }

            // Floating button: refresh recommendations in place via reloadToken.
            Button(action: { reloadToken += 1 }) {
                Image(systemName: "arrow.clockwise")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.blue)
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
            .padding(16)
        }
        .navigationTitle("BTA Feed (SwiftUI)")
    }
}
