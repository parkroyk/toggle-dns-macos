# ToggleDNS — macOS Menu Bar DNS Switcher

A native SwiftUI menu bar app that switches the active network interface's DNS between DHCP-provided servers and user-defined profiles.

## Build & Run

```bash
./build.sh                 # builds release binary, assembles dist/ToggleDNS.app
open dist/ToggleDNS.app    # launches the menu bar app
```

**Toolchain requirement:** The macOS 27 SDK expands SwiftUI's `@State` via the `SwiftUIMacros` macro plugin, which only ships with full Xcode (not Command Line Tools). `build.sh` automatically detects this and falls back to `/Applications/Xcode.app` when needed.

## Testing

```bash
DEVELOPER_DIR=/Applications/Xcode.app swift test
```

Tests are in `Tests/ToggleDNSTests/`. Currently covers the `networksetup -getdnsservers` output parser (which varies by macOS version).

## Architecture

- **DNSEngine.swift** — Shell wrapper around `route`, `networksetup`, and `osascript` for privileged DNS changes
- **AppModel.swift** — App state, profile persistence (UserDefaults), detection of current DNS state
- **PortTester.swift** — TCP port 53 reachability testing with latency measurement
- **Views/** — SwiftUI views for the menu bar popover and profile editor

## Key Implementation Notes

### DNS State Detection
`DNSEngine.manualDNS()` parses `networksetup -getdnsservers <service>` output. The "no servers" notice varies by macOS version (e.g., "There aren't any DNS servers set" vs "There aren't any DNS Servers set on Ethernet."). The parser (`parseDNSServers`) only keeps lines that look like actual server addresses (valid IP or hostname) to be robust against wording changes.

### Privileged Operations
DNS changes require admin privileges, executed via `osascript` with `with administrator privileges`. No privileged helper is installed — every DNS change triggers a password prompt.

### Quit Behavior
If a custom profile is active when the user quits, the app reverts to DHCP DNS first (admin prompt). If force-killed or the machine reboots while custom DNS is active, the next launch shows a "leftover DNS" banner offering one-tap revert.

## Limitations

- Admin password required for every DNS change
- Switching network interfaces doesn't auto-reapply the active profile
- No privileged helper installed (intentional trade-off)
