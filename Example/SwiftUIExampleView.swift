import SwiftUI
import BtaAudienzz

/// SwiftUI example — mirrors the Android app's BtaComposeActivity.
@available(iOS 14.0, *)
struct SwiftUIExampleView: View {

    private static let btaFeedId = "92692c82-cb38-4164-b77c-e89d56cb486d"

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("""
                    This is a sample article.\n\n\
                    The BTA (Below The Article) feed renders below once the \
                    SDK has loaded the widget.
                    """)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)

                // Remove debug/mockRecommendations in production.
                BtaFeedSwiftUI(btaFeedId: Self.btaFeedId)
                    .debug(true)
                    .mockRecommendations(true)
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
                    .frame(maxWidth: .infinity) // SwiftUI modifiers go after all BtaFeedSwiftUI modifiers
            }
        }
        .navigationTitle("BTA Feed (SwiftUI)")
    }
}
