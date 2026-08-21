# HotspotLens

HotspotLens is a native macOS Menu Bar application designed to monitor, identify, and manage devices connected to macOS Internet Sharing (Mobile Hotspot).

Unlike Windows Mobile Hotspot, macOS Internet Sharing lacks a native user interface for inspecting connected client IP addresses, hardware MAC addresses, vendor identification, connection history, and device blocking. HotspotLens fills this gap by leveraging macOS system networking primitives to provide real-time client visibility and kernel-level packet filter control.

## Key Features

- **Live Device Monitoring**: Scans the active hotspot bridge interface (`bridge100`) to detect active connected clients in real time.
- **Windows-Style Client Details**: Displays IPv4/IPv6 addresses, MAC addresses, and resolved OUI hardware vendor names (e.g., Apple, Realtek, Intel).
- **Device History & Logging**: Tracks connection history, first/last seen timestamps, sighting counts, and custom user-assigned device labels stored in an encrypted database.
- **Kernel-Level IP Blocking**: Blocks or unblocks specific client IP addresses using macOS Packet Filter (`pfctl`) anchor rules.
- **Menu Bar & Dock Interface**: Provides quick access via the macOS Menu Bar and standard application Dock icon.

## Architecture & How It Works

HotspotLens operates by aggregating data from multiple low-level macOS system sources and applying network filtering via system utilities.

### 1. Client Discovery Pipeline
- **DHCP Lease Reading**: Parses `/var/db/dhcpd_leases` to extract active IPv4 leases and client hostnames.
- **ARP Table Inspection**: Executes `/usr/sbin/arp -a -n` to map IPv4 addresses to MAC hardware addresses, scoped strictly to the active hotspot bridge (`bridge100`).
- **NDP Inspection**: Reads IPv6 Neighbor Discovery Protocol tables (`/usr/sbin/ndp -an`) to detect IPv6 client endpoints.
- **OUI Vendor Lookup**: Resolves the IEEE Organizationally Unique Identifier (OUI) from client MAC addresses against an embedded vendor database (`oui_vendors.json`). Randomized / Private Wi-Fi MAC addresses are identified and labeled appropriately.

### 2. Packet Filter (pf) Blocking Engine
- HotspotLens controls traffic using the macOS kernel Packet Filter (`pfctl`).
- Rules are generated in the format:
  ```pf
  block drop quick from <IP> to any
  block drop quick from any to <IP>
  ```
- Rules are loaded into system anchor `com.apple/hotspotlens` via `/etc/pf.anchors/com.hotspotlens.rules`.
- Anchor `com.apple/*` is automatically evaluated by `/etc/pf.conf`, ensuring immediate packet dropping without requiring modifications to the main system configuration file.

### 3. Encrypted History Persistence
- Device connection logs, custom labels, and block states are stored in SQLite via GRDB.
- Database records are encrypted at rest using AES-GCM 256-bit encryption managed by `EncryptedSQLiteContainer`.
- Symmetric keys are stored in macOS Keychain Services with fallback file protection.

## Repository Structure

```
HotspotLens/
├── App/
│   └── HotspotLensApp/          # macOS SwiftUI Application
│       ├── Dashboard/           # Devices, History, and Blocked tab views
│       ├── MenuBar/             # Menu Bar content controller
│       ├── Theme/               # Design system, colors, and typography
│       ├── ViewModels/          # Discovery, History, and Blocking coordinators
│       └── PrivilegedHelperManager.swift # Privileged helper manager & pfctl executor
├── Helper/
│   ├── HotspotLensHelper/       # Privileged Helper daemon implementation
│   │   ├── PFRuleManager.swift  # Packet Filter anchor management
│   │   └── main.swift           # XPC service listener
│   └── Shared/
│       └── HelperProtocol.swift # Inter-process communication (XPC) protocol
├── Sources/
│   ├── HotspotLensCore/         # Shared core framework
│   │   ├── Detection/           # ARP, DHCP, NDP readers & Discovery Service
│   │   ├── History/             # GRDB SQLite history store & encryption
│   │   ├── Vendor/              # OUI MAC vendor lookup engine
│   │   └── Resources/           # OUI vendor database (oui_vendors.json)
│   └── HotspotLensCLI/          # Command-line interface tool
├── Tests/
│   └── HotspotLensCoreTests/    # Automated unit test suite & system fixtures
├── Package.swift                # Swift Package Manager configuration
└── project.yml                  # XcodeGen project blueprint
```

## System Requirements

- **For End-Users**: macOS 14.0 (Sonoma) or later (Zero external dependencies required).
- **For Developers**: Xcode 15.0+, Swift 5.9+, and XcodeGen (`brew install xcodegen`).

## Installation & Setup

### For End-Users (Recommended)

No developer tools or terminal commands are needed.

1. Download **`HotspotLens-v1.0.0-macOS.zip`** from [GitHub Releases](https://github.com/100axe001/HotspotLens/releases).
2. Double-click the downloaded `.zip` file to extract `HotspotLens.app`.
3. Drag `HotspotLens.app` into your **Applications** folder.
4. Open `HotspotLens.app`!

### How to Use

1. **Enable Internet Sharing**: Open **System Settings > General > Sharing** and turn on **Internet Sharing** (Personal Hotspot).
2. **Connect Devices**: Connect your phone, tablet, or other computers to your Mac's hotspot.
3. **Monitor Clients**: Click the HotspotLens icon in your macOS Menu Bar to view connected devices, IP addresses, MAC addresses, and hardware vendors.
4. **Block Devices**: Click **Block** next to any connected device to drop its network traffic via macOS Packet Filter (`pfctl`).

### For Developers (Building From Source)

Generate the Xcode project and build from source:

```bash
# Install XcodeGen
brew install xcodegen

# Generate Xcode project blueprint
xcodegen generate

# Build Debug binary
xcodebuild -scheme HotspotLens -configuration Debug CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO build

# Launch compiled app
open ~/Library/Developer/Xcode/DerivedData/HotspotLens-*/Build/Products/Debug/HotspotLens.app
```

Alternatively, open `HotspotLens.xcodeproj` in Xcode and press `Cmd + R`.

### Running Tests

Execute the automated Swift test suite:

```bash
swift test
```

## Usage Guide

1. **Start Mobile Hotspot**: Enable Internet Sharing in **System Settings > General > Sharing > Internet Sharing**.
2. **View Connected Devices**: Click the HotspotLens icon in your macOS Menu Bar or open the main Dashboard window.
3. **Assign Custom Labels**: Double-click any device record to set a custom identifier (e.g., "My iPhone").
4. **Block a Device**: Click **Block** next to any connected device. When prompted for Administrator privileges, enter your password or use Touch ID once to authorize rule execution.
5. **Unblock a Device**: Navigate to the **Blocked** tab and click **Unblock** to restore internet connectivity.

## License

This project is open-source software licensed under the MIT License. See [LICENSE](LICENSE) for details.