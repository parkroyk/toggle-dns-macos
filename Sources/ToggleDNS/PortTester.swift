import Foundation
import Network

enum IPAddress {
    /// Validates an IPv4 or IPv6 literal address.
    static func isValid(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        var v4 = in_addr()
        if inet_pton(AF_INET, trimmed, &v4) == 1 { return true }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, trimmed, &v6) == 1 { return true }
        return false
    }
}

enum PortTester {
    /// Attempts a TCP connection to `host:53`.
    /// Returns the latency in milliseconds on success, or `nil` on failure/timeout.
    static func testPort53(_ host: String, timeoutSeconds: Double = 2.0) async -> Int? {
        await withCheckedContinuation { continuation in
            // All mutable state is guarded by `lock`.
            final class Box: @unchecked Sendable {
                var resumed = false
                let lock = NSLock()
            }
            let box = Box()
            let start = Date()
            let connection = NWConnection(host: NWEndpoint.Host(host), port: 53, using: .tcp)
            let queue = DispatchQueue(label: "dns.port53.test")

            @Sendable func finish(_ latency: Int?) {
                box.lock.lock()
                defer { box.lock.unlock() }
                guard !box.resumed else { return }
                box.resumed = true
                connection.cancel()
                continuation.resume(returning: latency)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(Int(Date().timeIntervalSince(start) * 1000))
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
                finish(nil)
            }
        }
    }
}
