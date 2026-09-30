import Foundation
import AppKit
import ServiceManagement

struct DNSProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    /// 1...4 validated DNS server addresses.
    var servers: [String]
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum DetectedState: Equatable {
        case unknown
        case noInterface
        case system
        case profile(UUID)
        /// Manual DNS is set but matches none of our profiles (e.g. leftover from a previous session).
        case other([String])
    }

    enum RowID: Hashable {
        case system
        case profile(UUID)
    }

    @Published var profiles: [DNSProfile] = []
    @Published var detected: DetectedState = .unknown
    @Published var busyRow: RowID? = nil
    @Published var launchAtLoginEnabled = false

    private let engine = DNSEngine()
    private var forceQuit = false
    private var quitRevertInProgress = false

    private static let profilesKey = "dns.profiles.v1"

    init() {
        loadProfiles()
        refreshLaunchAtLoginState()
    }

    // MARK: - Persistence

    func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: Self.profilesKey),
           let decoded = try? JSONDecoder().decode([DNSProfile].self, from: data) {
            profiles = decoded
        }
    }

    func persist() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: Self.profilesKey)
        }
    }

    // MARK: - Profile CRUD

    func saveProfile(_ profile: DNSProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        persist()
    }

    func deleteProfile(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        persist()
        Task { await refresh() }
    }

    // MARK: - Detection

    func refresh() async {
        guard let service = await engine.activeServiceName() else {
            detected = .noInterface
            return
        }
        let manual = await engine.manualDNS(service: service)
        if manual.isEmpty {
            detected = .system
        } else if let profile = profiles.first(where: { Set($0.servers) == Set(manual) }) {
            detected = .profile(profile.id)
        } else {
            detected = .other(manual)
        }
    }

    var isCustomActive: Bool {
        switch detected {
        case .profile, .other: return true
        default: return false
        }
    }

    // MARK: - Selection (apply / revert)

    func select(_ row: RowID) async {
        guard busyRow == nil else { return }
        if row == .system && detected == .system { return }
        if case let .profile(id) = row, detected == .profile(id) { return }

        do {
            guard let service = await engine.activeServiceName() else {
                presentAlert(messageText: "No active network interface",
                             informativeText: "Could not determine the current network interface. Check your connection and try again.")
                return
            }
            switch row {
            case .system:
                busyRow = .system
                try await engine.revertToDHCP(service: service)
                await engine.waitFor(manualDNS: [], service: service)
            case .profile(let id):
                guard let profile = profiles.first(where: { $0.id == id }) else { return }
                busyRow = .profile(id)
                try await engine.apply(servers: profile.servers, service: service)
                await engine.waitFor(manualDNS: profile.servers, service: service)
            }
        } catch AuthError.cancelled {
            presentAlert(messageText: "Authorization cancelled",
                         informativeText: "DNS settings were not changed.")
        } catch {
            let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            presentAlert(messageText: "Could not change DNS settings",
                         informativeText: detail)
        }
        busyRow = nil
        await refresh()
    }

    // MARK: - Launch at login

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            presentAlert(messageText: "Launch at login not updated",
                         informativeText: error.localizedDescription)
        }
        refreshLaunchAtLoginState()
    }

    func refreshLaunchAtLoginState() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Quit with revert

    /// Called from `NSApplicationDelegate.applicationShouldTerminate`.
    /// If a custom profile is active, reverts to DHCP (admin prompt) before terminating.
    func applicationShouldTerminate() -> NSApplication.TerminateReply {
        if forceQuit || quitRevertInProgress { return .terminateNow }
        guard isCustomActive else { return .terminateNow }
        startQuitRevert()
        return .terminateLater
    }

    private func startQuitRevert() {
        quitRevertInProgress = true
        Task { @MainActor in
            do {
                if let service = await engine.activeServiceName() {
                    try await engine.revertToDHCP(service: service)
                    await engine.waitFor(manualDNS: [], service: service)
                }
                forceQuit = true
                NSApp.terminate(nil)
            } catch {
                quitRevertInProgress = false
                let alert = NSAlert()
                alert.messageText = "Custom DNS is still active"
                alert.informativeText = "Reverting to DHCP-provided DNS requires authorization. You can try again, or quit without reverting."
                alert.addButton(withTitle: "Try Again")
                alert.addButton(withTitle: "Quit Anyway")
                if alert.runModal() == .alertFirstButtonReturn {
                    startQuitRevert()
                } else {
                    forceQuit = true
                    NSApp.terminate(nil)
                }
            }
        }
    }

    // MARK: - Alerts

    func presentAlert(messageText: String, informativeText: String? = nil) {
        let alert = NSAlert()
        alert.messageText = messageText
        if let informativeText {
            alert.informativeText = informativeText
        }
        alert.runModal()
    }
}

extension AppModel {
    var menuBarIcon: String {
        switch detected {
        case .profile, .other: return "network"
        default: return "globe"
        }
    }
}
