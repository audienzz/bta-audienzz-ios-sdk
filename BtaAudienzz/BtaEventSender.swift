import Foundation

/// Sends CloudEvents 1.0 batches to the Audienzz event ingester.
enum BtaEventSender {

    /// Temporary kill-switch for analytics ingestion.
    ///
    /// The `ws-event-ingester` endpoint currently returns HTTP 404, so we suppress the outbound
    /// request to avoid hammering a dead endpoint. The rest of the pipeline (collection, batching,
    /// consent gating) is unchanged, and the SDK's public API is unaffected. Flip back to `true`
    /// once the endpoint is live.
    private static let networkEnabled = false

    private static let endpoint = URL(
        string: "https://api.adnz.co/api/ws-event-ingester/submit/batch"
    )!

    static func send(_ events: [BtaEvent]) {
        guard networkEnabled else { return }

        let dicts = events.map { $0.toCloudEventDict() }
        guard let body = try? JSONSerialization.data(withJSONObject: dicts) else { return }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/cloudevents-batch+json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error = error {
                // No auto-retry — events are low-frequency so occasional loss is acceptable.
                print("[BtaEventSender] Failed to send events: \(error.localizedDescription)")
            }
        }.resume()
    }
}
