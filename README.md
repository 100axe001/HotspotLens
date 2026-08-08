# HotspotLens

A native macOS menu-bar utility for discovering, tracking, and managing devices connected to your Mac's Internet Sharing hotspot.

macOS lets you share your internet connection over Wi-Fi, Ethernet, or Bluetooth, but it doesn't give you a convenient built-in interface for seeing who's actually connected, how long they've been on, or blocking a client you don't recognize. HotspotLens fills that gap with real-time device discovery, connection history, and client management — entirely on-device, with no cloud, no account, and no telemetry.

---

## Table of Contents

- [Why This Exists](#why-this-exists)
- [Features](#features)
- [How It Works](#how-it-works)
- [System Architecture](#system-architecture)
- [Project Structure](#project-structure)
- [Tech Stack](#tech-stack)
- [Privacy](#privacy)
- [Development Status](#development-status)
- [Building From Source](#building-from-source)
- [Contributing](#contributing)

---

## Why This Exists

Apple's networking stack has no public API like `getHotspotClients()`. Internet Sharing is built on standard networking primitives — a bridge interface, DHCP, ARP — but there's no first-party way for an app to just ask "who's on my hotspot right now?"

That's a real gap for anyone who shares their connection regularly: you can't easily tell if a stranger guessed your Wi-Fi password, you can't see how many devices are actively pulling bandwidth, and you have no record of what's connected over time. HotspotLens is built to close that gap by reading the same underlying signals macOS itself uses internally, and presenting them in a clean, persistent, user-facing way.

**A note on framing:** this project doesn't claim "macOS has no way to know connected devices" — that's not accurate; the information is technically inspectable via `arp -a` today. The accurate claim is that **macOS doesn't provide a convenient, persistent, user-facing interface for it**, which is exactly what this app adds.

---

## Features

**Available in the current prototype (Phase 1):**
- ✅ Real-time Internet Sharing / hotspot status detection
- ✅ Active device discovery via ARP table + DHCP lease parsing
- ✅ MAC vendor lookup (Apple, Samsung, Google, etc. via OUI database)

**Planned (see [Development Status](#development-status)):**
- ⬜ Persistent connection history (first/last seen, connection count)
- ⬜ User-defined device labels
- ⬜ Unknown device alerts
- ⬜ Block / unblock clients
- ⬜ Menu-bar interface with live device list
- ⬜ Launch at login, notifications, dark/light mode
- ⬜ Export device history (JSON/CSV)

---

## How It Works

There is no single API for "connected hotspot clients," so HotspotLens combines several independent signals that macOS's networking stack already exposes, and cross-references them into one coherent device list:

| Signal | Source | Reliability |
|---|---|---|
| **Interface status** | `bridge100` (the interface Internet Sharing creates) | Primary — used to detect if sharing is active at all |
| **Subnet / gateway** | Parsed from the `inet` line of `ifconfig bridge100` | Primary |
| **Active clients** | `arp -a`, filtered to the sharing interface | Primary — most reliable live-client signal |
| **Supplementary leases** | `bootpd`'s DHCP lease file | Secondary — undocumented file location/format, used only to catch devices ARP's cache has already dropped |
| **Vendor identification** | MAC OUI prefix matched against a bundled JSON database | Best-effort labeling, not guaranteed identification |

None of this relies on a private/undocumented API call — it's the same information `arp -a` gives you in Terminal today, just parsed, merged, persisted, and made presentable.

---

## System Architecture

### High-Level Layers

```
┌─────────────────────────────────────────────────────────┐
│                     PRESENTATION LAYER                   │
│  SwiftUI Views (Menu Bar + Main Window)                  │
│  ViewModels (MVVM)                                        │
└───────────────────────┬───────────────────────────────────┘
                         │
┌───────────────────────▼───────────────────────────────────┐
│                      DOMAIN LAYER                          │
│  DeviceDiscoveryService   HotspotMonitor                   │
│  DeviceHistoryStore       FirewallManager (protocol)        │
│  VendorLookupService      NotificationService                │
└───────────────────────┬───────────────────────────────────┘
                         │
┌───────────────────────▼───────────────────────────────────┐
│                  SYSTEM INTEGRATION LAYER                  │
│  ARP/NDP reader   DHCP lease reader   Interface monitor      │
│  XPC client → Privileged Helper (firewall ops)                │
└───────────────────────┬───────────────────────────────────┘
                         │ XPC (Mach IPC)
┌───────────────────────▼───────────────────────────────────┐
│              PRIVILEGED HELPER (separate binary)           │
│  Runs as root via SMAppService                              │
│  Executes pf rules or Network Extension calls                │
└───────────────────────┬───────────────────────────────────┘
                         │
┌───────────────────────▼───────────────────────────────────┐
│                          macOS                              │
│  Internet Sharing (bridge100) · ARP table · DHCP leases      │
│  pfctl / Network Extension                                   │
└─────────────────────────────────────────────────────────┘
```

Two processes, always. The GUI app never touches the network stack directly for privileged operations — it only talks to the helper over XPC. This separation is required for both security and eventual App sandboxing/notarization.

### Component Responsibilities

| Component | Responsibility | Runs in |
|---|---|---|
| `HotspotMonitor` | Detects if Internet Sharing is on, which interface (`bridge100`), what subnet | Main app |
| `DeviceDiscoveryService` | Merges ARP table + DHCP leases into a unified device list | Main app |
| `VendorLookupService` | Resolves MAC OUI prefix → vendor name | Main app, local DB |
| `DeviceHistoryStore` | Persists devices (first/last seen, connection count, labels) | Main app |
| `NotificationService` | Fires "new device joined" alerts | Main app |
| `FirewallManager` (protocol) | Abstract block/unblock interface | Main app (calls out via XPC) |
| Privileged Helper | Actually blocks/unblocks via `pf` or Network Extension | Separate root process |

### Discovery Data Flow

```
Timer (every N sec)
   → HotspotMonitor.currentStatus()
   → if active: DeviceDiscoveryService.scan()
        → read `arp -a`, filter to hotspot interface
        → read DHCP lease file (supplementary)
        → merge + dedupe by MAC
        → resolve vendor via VendorLookupService
   → DeviceHistoryStore.upsert(devices)   [planned]
   → diff against previous scan
        → new MAC not in history? → NotificationService.alertNewDevice()   [planned]
   → publish to ViewModel → SwiftUI re-renders   [planned]
```

### Block Action Data Flow (planned)

```
User taps [Block] in UI
   → FirewallManager.block(device)
   → XPC message to Privileged Helper
   → Helper validates request, applies pf rule / NE filter
   → Helper returns success/failure over XPC
   → DeviceHistoryStore.markBlocked(device)
   → UI updates
```

---

## Project Structure

The current repo contains the **Phase 1 discovery prototype** — a standalone Swift Package Manager command-line tool used to validate ARP/DHCP/interface parsing before any SwiftUI or persistence code is built on top of it. The layout below shows both what exists today and the fuller app structure it will grow into.

### Current: Discovery Prototype (`HotspotLensCLI/`)

```
HotspotLensCLI/
├── Package.swift
└── Sources/
    └── HotspotLensCLI/
        ├── main.swift                     # CLI entry point, wires everything together
        │
        ├── Models/
        │   ├── Device.swift                # Core device model + MACAddress wrapper
        │   └── HotspotStatus.swift         # Interface/subnet snapshot
        │
        ├── Services/
        │   ├── HotspotMonitor.swift        # Detects bridge100, derives subnet
        │   ├── ARPTableReader.swift        # Parses `arp -a` output
        │   ├── DHCPLeaseReader.swift       # Parses bootpd lease file
        │   ├── VendorLookupService.swift   # OUI → vendor name lookup
        │   └── DeviceDiscoveryService.swift # Merges all signals into device list
        │
        └── Resources/
            └── oui-vendor-db.json          # MAC vendor prefix database
```

### Target: Full macOS App

```
HotspotLens/
│
├── HotspotLens.xcodeproj
├── README.md
├── LICENSE
├── CONTRIBUTING.md
├── CHANGELOG.md
│
├── App/
│   ├── HotspotLensApp.swift          # @main entry point
│   ├── AppDelegate.swift             # menu bar item setup, lifecycle
│   └── Info.plist
│
├── Features/
│   ├── MenuBar/
│   │   ├── MenuBarView.swift
│   │   └── MenuBarViewModel.swift
│   │
│   ├── Dashboard/
│   │   ├── DashboardView.swift
│   │   └── DashboardViewModel.swift
│   │
│   ├── Devices/
│   │   ├── DeviceListView.swift
│   │   ├── DeviceDetailView.swift
│   │   ├── DeviceRowView.swift
│   │   └── DeviceListViewModel.swift
│   │
│   ├── History/
│   │   ├── HistoryView.swift
│   │   └── HistoryViewModel.swift
│   │
│   ├── Blocked/
│   │   ├── BlockedDevicesView.swift
│   │   └── BlockedDevicesViewModel.swift
│   │
│   └── Settings/
│       ├── SettingsView.swift
│       └── SettingsViewModel.swift
│
├── Core/
│   ├── Models/
│   │   ├── Device.swift
│   │   ├── HotspotStatus.swift
│   │   └── VendorInfo.swift
│   │
│   ├── Services/
│   │   ├── HotspotMonitor.swift
│   │   ├── DeviceDiscoveryService.swift
│   │   ├── ARPTableReader.swift
│   │   ├── DHCPLeaseReader.swift
│   │   ├── VendorLookupService.swift
│   │   ├── DeviceHistoryStore.swift
│   │   └── NotificationService.swift
│   │
│   └── Firewall/
│       ├── FirewallManager.swift     # protocol
│       ├── XPCFirewallClient.swift   # talks to helper
│       └── FirewallError.swift
│
├── HelperTool/                       # SEPARATE target — privileged helper
│   ├── main.swift
│   ├── HelperXPCListener.swift
│   ├── PFFirewallBackend.swift       # or NetworkExtensionBackend.swift
│   ├── HelperProtocol.swift
│   └── Info.plist
│
├── Shared/
│   └── XPCProtocol.swift             # code shared between App and HelperTool targets
│
├── Infrastructure/
│   ├── Persistence/
│   │   ├── SchemaV1.swift
│   │   └── PersistenceController.swift
│   ├── Logging/
│   │   └── Logger+Categories.swift
│   └── Resources/
│       └── oui-vendor-db.json
│
├── Tests/
│   ├── HotspotLensTests/
│   │   ├── ARPTableReaderTests.swift
│   │   ├── DeviceHistoryStoreTests.swift
│   │   └── VendorLookupServiceTests.swift
│   └── HotspotLensUITests/
│
└── .github/
    └── workflows/
        └── ci.yml
```

**Why the Privileged Helper is a separate target:** it must be a distinct signed executable, embedded under `Contents/Library/LaunchServices/` and registered via `SMAppService.daemon(...)`. It cannot share a process with the SwiftUI app — that separation is what makes privileged network operations auditable and keeps the main app's attack surface small.

---

## Tech Stack

| Layer | Choice |
|---|---|
| Language | Swift 5.9+ |
| UI | SwiftUI (no Electron/Tauri — native only) |
| Editor | VS Code / Antigravity (or any editor with Swift LSP support) |
| Build | Xcode Command Line Tools (`swift build`, `xcodebuild`, `xcrun notarytool`) |
| Package management | Swift Package Manager |
| Persistence (planned) | SwiftData or SQLite (GRDB.swift), optionally SQLCipher for at-rest encryption |
| Privileged operations (planned) | XPC + `SMAppService` + Network Extension |
| Distribution | Developer ID signing + notarization, `.dmg` via GitHub Releases |

Full tool-by-tool rationale lives in the architecture notes above and in `CONTRIBUTING.md`.

---

## Privacy

Privacy is a core design constraint, not an afterthought:

- **Everything stays on your Mac.** No telemetry, no analytics SDKs, no cloud sync, no account system.
- **No external calls.** Vendor lookup uses a bundled local JSON file, not a network API.
- **History is yours to delete.** Per-device and bulk history clearing are planned as first-class features, not buried settings.
- **Local storage will be encrypted at rest** once the persistence layer lands, since MAC addresses and connection timestamps are effectively a log of "who has been near/using your network and when."

A broader note on scope: this tool gives a network owner visibility into their **own** hotspot — the same category of feature shipped in every consumer router admin panel. The block/unblock feature is intended for managing your own network (e.g., a stranger who guessed your password), not for covertly monitoring or controlling specific people who share your trust. No stealth/hidden-blocking mode is planned, and none should be added without real discussion — that would change what this tool is for.

---

## Development Status

Currently in **Phase 1 — Detection**, per the phased build plan:

- [x] **Phase 1 — Detection:** hotspot status, ARP/DHCP parsing, vendor lookup (standalone CLI prototype)
- [ ] **Phase 2 — History:** persistent device store, first/last seen, connection counts, user labels
- [ ] **Phase 3 — Block/Unblock:** privileged helper, XPC, `FirewallManager` implementation
- [ ] **Phase 4 — Polish:** menu-bar UI, notifications, auto-refresh, launch at login, export

The current codebase is a command-line-only discovery prototype — no SwiftUI, no persistence, no blocking yet. See `Development Status` above for what's real vs. planned.

---

## Building From Source

```bash
git clone https://github.com/<your-username>/HotspotLens.git
cd HotspotLens/HotspotLensCLI
swift build
```

Run the discovery prototype:

```bash
swift run
```

**Requirements:**
- macOS 13+ (Ventura or later)
- Xcode Command Line Tools installed (`xcode-select --install`)
- Internet Sharing enabled in System Settings → General → Sharing, to see any output beyond "hotspot inactive"

---

## Contributing

Contributions are welcome — see `CONTRIBUTING.md` for setup details and coding conventions once it's added. If you're touching anything under `Firewall/` or `HelperTool/`, please open an issue to discuss the approach first, since privileged network operations are the most security-sensitive part of this project.

## License

See `LICENSE`.