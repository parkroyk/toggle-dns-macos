import Foundation

enum AuthError: LocalizedError {
    case cancelled
    case commandFailed(String)

    var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Authorization was cancelled."
        case .commandFailed(let detail):
            return detail
        }
    }
}

/// Stateless wrapper around `route` / `networksetup` / `osascript`.
final class DNSEngine {
    struct ShellResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    // MARK: - Shell helper

    static func run(_ launchPath: String, _ arguments: [String]) async -> ShellResult {
        await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: launchPath)
                process.arguments = arguments
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: ShellResult(
                        exitCode: process.terminationStatus,
                        stdout: String(data: outData, encoding: .utf8) ?? "",
                        stderr: String(data: errData, encoding: .utf8) ?? ""))
                } catch {
                    continuation.resume(returning: ShellResult(
                        exitCode: -1, stdout: "", stderr: error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Read state (no privileges needed)

    /// Network service name (e.g. "Wi-Fi") of the interface holding the default route.
    func activeServiceName() async -> String? {
        let route = await Self.run("/sbin/route", ["-n", "get", "default"])
        guard route.exitCode == 0 else { return nil }
        var device: String?
        for line in route.stdout.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("interface:") {
                device = trimmed.components(separatedBy: ":").last?
                    .trimmingCharacters(in: .whitespaces)
                break
            }
        }
        guard let device else { return nil }
        return await serviceName(forDevice: device)
    }

    func serviceName(forDevice device: String) async -> String? {
        let result = await Self.run("/usr/sbin/networksetup", ["-listallhardwareports"])
        guard result.exitCode == 0 else { return nil }
        var currentPort: String?
        for line in result.stdout.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Hardware Port:") {
                currentPort = String(trimmed.dropFirst("Hardware Port:".count))
                    .trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Device:") {
                let name = String(trimmed.dropFirst("Device:".count))
                    .trimmingCharacters(in: .whitespaces)
                if name == device, let port = currentPort {
                    return port
                }
            }
        }
        return nil
    }

    /// Manually configured DNS servers for a service. Empty when none are set (i.e. DHCP).
    func manualDNS(service: String) async -> [String] {
        let result = await Self.run("/usr/sbin/networksetup", ["-getdnsservers", service])
        guard result.exitCode == 0 else { return [] }
        return Self.parseDNSServers(result.stdout)
    }

    /// Parses `networksetup -getdnsservers` output into server addresses.
    /// The "no servers configured" notice is not a stable string across macOS
    /// versions (e.g. "There aren't any DNS servers set" vs.
    /// "There aren't any DNS Servers set on Ethernet."), so only lines that
    /// actually look like an IP address or hostname are kept.
    static func parseDNSServers(_ output: String) -> [String] {
        var servers: [String] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  trimmed.rangeOfCharacter(from: .whitespaces) == nil,
                  IPAddress.isValid(trimmed) || isPlausibleHostname(trimmed)
            else { continue }
            servers.append(trimmed)
        }
        return servers
    }

    private static func isPlausibleHostname(_ value: String) -> Bool {
        guard value.count <= 253 else { return false }
        let labels = value.split(separator: ".", omittingEmptySubsequences: true)
        return !labels.isEmpty && labels.allSatisfy { label in
            (1...63).contains(label.count)
                && label.first != "-" && label.last != "-"
                && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }

    // MARK: - Apply changes (admin privileges required)

    func apply(servers: [String], service: String) async throws {
        var command = "/usr/sbin/networksetup -setdnsservers " + shellQuote(service)
        for server in servers {
            command += " " + shellQuote(server)
        }
        try await privileged(command)
    }

    /// Removes manual DNS so the DHCP-provided servers take effect again.
    func revertToDHCP(service: String) async throws {
        try await privileged("/usr/sbin/networksetup -setdnsservers " + shellQuote(service) + " Empty")
    }

    private func privileged(_ command: String) async throws {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        let result = await Self.run("/usr/bin/osascript", ["-e", script])
        guard result.exitCode == 0 else {
            let stderr = result.stderr.lowercased()
            if stderr.contains("user canceled") || stderr.contains("-128") {
                throw AuthError.cancelled
            }
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AuthError.commandFailed(detail.isEmpty ? "The privileged command failed." : detail)
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Wait for state to settle

    func waitFor(manualDNS expected: [String], service: String, timeout: Double = 6) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let current = await manualDNS(service: service)
            if Set(current) == Set(expected) { return }
        }
    }
}
