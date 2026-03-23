import Foundation

/// Sends CloudEvents 1.0 batches to the Audienzz event ingester.
enum BtaEventSender {

    private static let endpoint = URL(
        string: "https://dev-api.adnz.co/api/ws-event-ingester/submit/batch"
    )!

    static func send(_ events: [BtaEvent]) {
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
