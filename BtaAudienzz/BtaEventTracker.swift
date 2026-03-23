import Foundation

/// Collects analytics events and sends them in batches to the Audienzz ingester.
///
/// Batching: events are queued in memory and flushed 2 seconds after the last tracked event
/// (debounce), matching the Android SDK's behaviour.
final class BtaEventTracker {

    static let shared = BtaEventTracker()

    /// Unique ID for the current app process.
    let sessionId = UUID().uuidString

    private var visitorId: String?
    private var eventQueue: [BtaEvent] = []
    private let lock = NSLock()
    private var debounceWorkItem: DispatchWorkItem?
    private let sendQueue = DispatchQueue(label: "org.audienzz.bta.events", qos: .utility)

    private init() {}

    // MARK: - Public

    func initialize() {
        if visitorId == nil {
            visitorId = BtaVisitorId.getOrCreate()
        }
    }

    func track(_ event: BtaEvent) {
        var enriched = event
        enriched.visitorId = visitorId ?? ""

        lock.lock()
        eventQueue.append(enriched)
        lock.unlock()

        scheduleSend()
    }

    // MARK: - Private

    private func scheduleSend() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.flush()
        }
        debounceWorkItem = workItem
        sendQueue.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    private func flush() {
        lock.lock()
        let events = eventQueue
        eventQueue.removeAll()
        lock.unlock()

        guard !events.isEmpty else { return }
        BtaEventSender.send(events)
    }
}
