# Toggle DNS — macOS menu bar app

A small native macOS menu bar utility that switches the active network interface's DNS
between DHCP-provided servers and user-defined profiles.

## Features

- **Menu bar icon** with a popover (icon changes: globe = system DNS, network = custom DNS)
- **Profiles**: named sets of 1–4 DNS servers, stored in `UserDefaults`
- **Reachability testing**: every server entry is TCP-tested on port 53 (with latency shown)
  before the profile can be saved — Save stays disabled until all entered servers pass
- **Toggle**: select "System (DHCP)" or any profile; changes go through
  `networksetup -setdnsservers` with a standard admin password prompt
- **Revert on exit**: quitting while a custom profile is active first reverts to DHCP DNS
  (admin prompt, with Try Again / Quit Anyway if cancelled)
- **Leftover detection**: if manual DNS from a previous session is still applied at launch,
  a banner offers one-tap revert
- **Launch at login** via `SMAppService`

## Requirements

- macOS 14+
- Xcode Command Line Tools (`xcode-select --install`) — full Xcode not needed

## Build & run

```bash
./build.sh                 # builds release binary, assembles dist/ToggleDNS.app, ad-hoc signs it
open dist/ToggleDNS.app    # launches the menu bar app
```

Optional install:

```bash
cp -R dist/ToggleDNS.app /Applications/
```

## Usage

1. Click the menu bar icon → **New Profile**.
2. Enter a name and 1–4 DNS servers (e.g. `1.1.1.1`, `8.8.8.8`). Each valid entry is
   automatically tested for port-53 reachability; wait for green checkmarks.
3. **Save**, then click the profile row in the popover and approve the password prompt.
4. Click **System (DHCP)** at any time to restore DHCP-provided servers.

## How it works

- Active interface: default route (`route -n get default`) → mapped to a `networksetup`
  service name via `-listallhardwareports`.
- Current state: `networksetup -getdnsservers <service>` — empty means DHCP is in effect;
  a list matching one of your profiles marks that profile active.
- Applying/reverting: `osascript … with administrator privileges` runs
  `networksetup -setdnsservers <service> <servers…>` or `… Empty`.

## Limitations

- An admin password is required for every DNS change (no privileged helper installed).
- If the app is force-killed (or the machine reboots) while custom DNS is active, the next
  launch shows the leftover-DNS banner so you can revert.
- Switching network interfaces (Wi-Fi ↔ Ethernet) does not automatically re-apply the
  active profile to the new interface — select it again from the popover.
