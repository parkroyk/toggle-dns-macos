import SwiftUI

struct ProfileEditorView: View {
    @EnvironmentObject var model: AppModel

    let profile: DNSProfile?
    let onDone: () -> Void

    enum ServerTest: Equatable {
        case idle
        case testing
        case invalidFormat
        case ok(Int)   // latency in ms
        case failed
    }

    @State private var name: String
    @State private var servers: [String]
    @State private var tests: [ServerTest]
    @State private var generations: [Int]

    init(profile: DNSProfile?, onDone: @escaping () -> Void) {
        self.profile = profile
        self.onDone = onDone
        _name = State(initialValue: profile?.name ?? "")
        let existing = profile?.servers ?? []
        var padded = Array(repeating: "", count: 4)
        for (index, value) in existing.enumerated() where index < 4 {
            padded[index] = value
        }
        _servers = State(initialValue: padded)
        _tests = State(initialValue: Array(repeating: .idle, count: 4))
        _generations = State(initialValue: Array(repeating: 0, count: 4))
    }

    private var canSave: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return false }
        guard IPAddress.isValid(servers[0]) else { return false }
        for (server, test) in zip(servers, tests) {
            let value = server.trimmingCharacters(in: .whitespaces)
            if value.isEmpty { continue }
            if case .ok = test { continue }
            return false
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button(action: onDone) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                Text(profile == nil ? "New Profile" : "Edit Profile")
                    .font(.headline)
                Spacer()
            }

            TextField("Profile name", text: $name)
                .textFieldStyle(.roundedBorder)

            VStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { index in
                    serverRow(index)
                }
            }

            Text("Every server is tested for TCP port 53 reachability before it can be saved.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if let profile {
                    Button(role: .destructive) {
                        model.deleteProfile(profile.id)
                        onDone()
                    } label: {
                        Text("Delete")
                    }
                }
                Spacer()
                Button("Cancel", action: onDone)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(14)
        .onAppear {
            for index in servers.indices where !servers[index].isEmpty {
                scheduleTest(index)
            }
        }
    }

    // MARK: - Server row

    private func serverRow(_ index: Int) -> some View {
        HStack(spacing: 8) {
            Text("Server \(index + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            TextField(index == 0 ? "e.g. 1.1.1.1 (required)" : "e.g. 8.8.8.8 (optional)",
                      text: bindingFor(index))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onChange(of: servers[index]) { _, _ in
                    scheduleTest(index)
                }
            testIndicator(index)
                .frame(width: 84, alignment: .trailing)
        }
    }

    private func bindingFor(_ index: Int) -> Binding<String> {
        Binding(
            get: { servers[index] },
            set: { servers[index] = $0 }
        )
    }

    @ViewBuilder
    private func testIndicator(_ index: Int) -> some View {
        switch tests[index] {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("testing")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .ok(let ms):
            Label("\(ms) ms", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .failed:
            Label("unreachable", systemImage: "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        case .invalidFormat:
            Label("invalid IP", systemImage: "exclamationmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Testing

    private func scheduleTest(_ index: Int) {
        let generation = generations[index] &+ 1
        generations[index] = generation
        let value = servers[index].trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else {
            tests[index] = .idle
            return
        }
        guard IPAddress.isValid(value) else {
            tests[index] = .invalidFormat
            return
        }
        tests[index] = .testing
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard generation == generations[index] else { return }
            let latency = await PortTester.testPort53(value)
            guard generation == generations[index] else { return }
            tests[index] = (latency != nil) ? .ok(latency!) : .failed
        }
    }

    // MARK: - Save

    private func save() {
        guard canSave else { return }
        let cleaned = servers
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var result = profile ?? DNSProfile(id: UUID(), name: "", servers: [])
        result.name = name.trimmingCharacters(in: .whitespaces)
        result.servers = cleaned
        model.saveProfile(result)
        onDone()
        Task { await model.refresh() }
    }
}
