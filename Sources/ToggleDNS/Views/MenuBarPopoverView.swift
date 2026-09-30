import SwiftUI
import AppKit

struct MenuBarPopoverView: View {
    @EnvironmentObject var model: AppModel
    @State private var showEditor = false
    @State private var editingProfile: DNSProfile?

    var body: some View {
        Group {
            if showEditor {
                ProfileEditorView(profile: editingProfile) {
                    showEditor = false
                }
            } else {
                listView
            }
        }
        .frame(width: 340)
        .onAppear {
            Task { await model.refresh() }
        }
    }

    // MARK: - Main list

    private var listView: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if case .other(let servers) = model.detected {
                leftoverBanner(servers)
            }
            rows
            Button {
                editingProfile = nil
                showEditor = true
            } label: {
                Label("New Profile", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Divider()

            HStack {
                Toggle(isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }
                )) {
                    Text("Launch at Login")
                }
                .toggleStyle(.checkbox)
                .font(.callout)

                Spacer()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.borderless)
                .help("Quit ToggleDNS (reverts custom DNS first)")
            }
        }
        .padding(14)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: model.menuBarIcon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Toggle DNS")
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    private var statusText: String {
        switch model.detected {
        case .system:
            return "System (DHCP) DNS"
        case .profile(let id):
            guard let profile = model.profiles.first(where: { $0.id == id }) else {
                return "Custom DNS active"
            }
            return "\(profile.name) — \(profile.servers.joined(separator: ", "))"
        case .other(let servers):
            return "Manual DNS: \(servers.joined(separator: ", "))"
        case .noInterface:
            return "No active network interface"
        case .unknown:
            return "Detecting…"
        }
    }

    @ViewBuilder
    private var rows: some View {
        VStack(spacing: 4) {
            rowView(id: .system,
                    title: "System (DHCP)",
                    subtitle: "DNS servers provided by your network",
                    editAction: nil)
            ForEach(model.profiles) { profile in
                rowView(id: .profile(profile.id),
                        title: profile.name,
                        subtitle: profile.servers.joined(separator: ",  "),
                        editAction: {
                            editingProfile = profile
                            showEditor = true
                        })
            }
        }
    }

    private func leftoverBanner(_ servers: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Unrecognized manual DNS is set — possibly a leftover from a previous session.",
                  systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
            Button {
                Task { await model.select(.system) }
            } label: {
                Text("Revert to DHCP DNS")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Row

    private func rowView(id: AppModel.RowID, title: String, subtitle: String, editAction: (() -> Void)?) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { await model.select(id) }
            } label: {
                HStack(spacing: 8) {
                    statusSymbol(for: id)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.body)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.busyRow != nil)

            if let editAction {
                Button(action: editAction) {
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Edit profile")
                .disabled(model.busyRow != nil)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected(id) ? Color.accentColor.opacity(0.12) : Color.clear)
        )
    }

    @ViewBuilder
    private func statusSymbol(for id: AppModel.RowID) -> some View {
        if model.busyRow == id {
            ProgressView()
                .controlSize(.small)
        } else if isSelected(id) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.accentColor)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.secondary.opacity(0.4))
        }
    }

    private func isSelected(_ id: AppModel.RowID) -> Bool {
        switch (id, model.detected) {
        case (.system, .system):
            return true
        case let (.profile(profileID), .profile(detectedID)):
            return profileID == detectedID
        default:
            return false
        }
    }
}
