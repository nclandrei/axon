# axon

macOS Accessibility CLI for AI agent workflows.

## The Problem

AI agents can't reliably drive macOS apps. AppleScript is fragile and unreliable. The macOS Accessibility API (AXUIElement) is actually solid and well-maintained — but nobody has wrapped it in a clean CLI that agents can call over SSH.

axon fixes this. It's the equivalent of Playwright for web or XCUITest for iOS, but for native macOS apps running in a VM or secondary user session.

## Install

Build from source (requires macOS 14+ and Xcode 15+):

```bash
git clone <repo>
cd axon
swift build -c release
cp .build/release/axon /usr/local/bin/axon
```

Or use the Makefile:

```bash
make install
```

No external dependencies — only Cocoa and CoreGraphics frameworks.

## How Agents Use This

axon follows the [rodney](https://github.com/simonw/rodney)/[showboat](https://github.com/simonw/showboat) pattern: a single `--help` gives the AI agent everything it needs — all commands, all flags, element targeting rules, exit codes, output format, and full workflow examples.

```bash
axon --help              # comprehensive reference — all commands, flags, and examples
axon tree --help         # per-command details if needed
```

No MCP server needed — the CLI is the interface.

## Agent Workflow

```bash
# 1. Launch the app
axon launch --name TextEdit

# 2. Read the UI state
axon tree --app TextEdit --compact

# 3. Visually verify
axon screenshot --app TextEdit

# 4. Interact
axon click --app TextEdit --label "Save"
axon type --app TextEdit --path "AXWindow[0]/AXScrollArea[0]/AXTextArea[0]" --text "Hello"

# 5. Wait for async UI
axon wait --app TextEdit --label "Saved" --appear --timeout 5

# 6. Close when done
axon close --app TextEdit --quit
```

All over SSH into a Tart VM or secondary user session.

## Commands

All commands output JSON to stdout. Errors go to stderr with non-zero exit codes.
Run `axon <command> --help` for full details on any command.

### list

List all running GUI apps.

```bash
axon list
```

### launch

Launch an app by name, bundle ID, or path. Waits up to 5s for it to start.

```bash
axon launch --name TextEdit
axon launch --bundle-id com.apple.Safari
axon launch --path /Applications/Xcode.app
```

### tree

Dump the accessibility tree as JSON. Each node gets a `path` field for stable addressing.

```bash
axon tree --app Finder --compact
axon tree --app Finder --depth 3
```

### click

Click a UI element. Activates the app first.

```bash
axon click --app MyApp --identifier saveButton
axon click --app MyApp --label "Save"
axon click --app MyApp --path "AXWindow[0]/AXGroup[0]/AXButton[2]"
```

### type

Type text into a field. Direct value set, falls back to keyboard events.

```bash
axon type --app TextEdit --path "AXWindow[0]/AXScrollArea[0]/AXTextArea[0]" --text "Hello"
axon type --app MyApp --identifier searchField --text "query" --clear
```

### scroll

Scroll within an element.

```bash
axon scroll --app Safari --path "AXWindow[0]/AXScrollArea[0]" --direction down --amount 10
```

### screenshot

Capture a window or full screen as PNG at Retina resolution.

```bash
axon screenshot --app Finder
axon screenshot --app Xcode --window "MyProject" --output ~/Desktop/shot.png
axon screenshot --app Finder --full-screen
```

### activate

Bring an app to the front.

```bash
axon activate --app Finder
```

### close

Close a window or quit an app.

```bash
axon close --app TextEdit                    # close frontmost window
axon close --app Xcode --window "MyProject"  # close specific window
axon close --app TextEdit --quit             # quit entirely
```

### wait

Wait for an element to appear or disappear. Polls every 200ms.

```bash
axon wait --app MyApp --identifier loadingSpinner --disappear --timeout 30
axon wait --app MyApp --label "Welcome" --appear
```

### vm-bake

Clone a stock Tart image into a reusable per-app base. The new VM is left
stopped — run it manually (`tart run <name>`), install your app, grant
accessibility and screen-recording permissions, then `tart stop <name>`. The
sealed VM is now a per-app template: every later `vm-acquire --base <name>`
clones it in milliseconds via APFS COW, skipping the slow setup step on every
parallel run.

```bash
axon vm-bake --source ghcr.io/cirruslabs/macos-sonoma-base:latest --name axon-textedit-base
tart run axon-textedit-base    # configure once: install the app, grant AX/SR
tart stop axon-textedit-base   # seal it
```

Output:

```json
{
  "success": true,
  "name": "axon-textedit-base",
  "source": "ghcr.io/cirruslabs/macos-sonoma-base:latest"
}
```

### vm-acquire

Clone, boot, and register an ephemeral macOS VM via [Tart](https://github.com/cirruslabs/tart).
The clone is instant (APFS COW), and the command waits for the VM to acquire an
IP before returning. Registers the VM in `~/.axon/vms.json` so `vm-list` and
`vm-release --all` can find it.

Pass either a stock image or a base produced by `vm-bake`.

```bash
axon vm-acquire --base sonoma-base --headless
axon vm-acquire --base ghcr.io/cirruslabs/macos-sonoma-base:latest --timeout 120
```

Output:

```json
{
  "success": true,
  "name": "axon-12ab34cd",
  "base": "sonoma-base",
  "created": "2026-04-11T10:30:00Z",
  "ip": "192.168.64.10"
}
```

### vm-release

Stop and delete an axon-managed VM, or release every VM in the registry at once.

```bash
axon vm-release --name axon-12ab34cd     # release one
axon vm-release --all                    # release every registered VM
```

`--all` exits non-zero if any individual delete failed; the JSON includes both
counts so callers can decide what to do.

### vm-list

List every VM currently in `~/.axon/vms.json`. Returns an empty list (not an
error) when no VMs have been acquired yet.

```bash
axon vm-list
axon vm-list | jq '.vms[].ip'
```

## Error Handling

Errors include context to help agents self-correct:

```json
{
  "error": "element_not_found",
  "message": "No element with identifier 'saveBtn' found in MyApp",
  "available": ["cancelBtn", "submitBtn", "AXButton:OK"]
}
```

## Element Selection Priority

1. **Accessibility identifier** — fastest and most stable
2. **Exact title/label match**
3. **Case-insensitive contains match** on title/label
4. **Tree path** — structural addressing like `AXWindow[0]/AXGroup[1]/AXButton[0]`

When multiple elements match, enabled elements are preferred.

## Accessibility Permissions

Add your terminal app to **System Settings > Privacy & Security > Accessibility**.

For VMs: grant permissions to the SSH server process (`sshd`).

## Recommended VM Setup

Use [Tart](https://github.com/cirruslabs/tart) for headless macOS VMs on Apple
Silicon. axon ships built-in lifecycle commands so you don't need to wrap
`tart` yourself:

```bash
# 1. One-time: pull a stock base with Tart
tart pull ghcr.io/cirruslabs/macos-sonoma-base:latest

# 2. Acquire an ephemeral clone (instant via APFS COW, waits for IP)
axon vm-acquire --base ghcr.io/cirruslabs/macos-sonoma-base:latest --headless

# 3. SSH in and drive UI via axon
ssh admin@$(axon vm-list | jq -r '.vms[-1].ip')

# 4. When done, release the clone
axon vm-release --name axon-12ab34cd

# Or nuke every clone at once
axon vm-release --all
```

The registry lives at `~/.axon/vms.json`.

### Per-app base images for parallel work

Pulling and booting a stock VM is slow; installing your app and granting AX
permissions inside it is slower. Do that work once with `vm-bake`, then clone
the sealed result every run:

```bash
# 1. One-time per app: bake a per-app base
axon vm-bake --source ghcr.io/cirruslabs/macos-sonoma-base:latest --name axon-myapp-base
tart run  axon-myapp-base    # install your app, grant AX + screen recording
tart stop axon-myapp-base    # seal it

# 2. Per run: clone the sealed base. Each clone is independent.
axon vm-acquire --base axon-myapp-base --headless
axon vm-acquire --base axon-myapp-base --headless
axon vm-acquire --base axon-myapp-base --headless
```

Three parallel `vm-acquire` calls give you three isolated VMs (separate
filesystems, AX trees, windows) that all skip the install-and-permission step.
Working on multiple apps? Bake one base per app (`axon-myapp-base`,
`axon-otherapp-base`, …) and acquire from whichever you need.

## Architecture

```
Sources/
├── axon/
│   └── main.swift          CLI entry, comprehensive --help, command dispatch
└── AxonLib/
    ├── Models.swift        AXNode and Codable JSON output types
    ├── AXHelpers.swift     AXUIElement wrappers, tree walking, element finding
    ├── AppDiscovery.swift  Find running apps by name or bundle ID
    ├── Actions.swift       launch, click, type, scroll, activate, close, wait
    ├── Screenshot.swift    CGWindowListCreateImage capture
    ├── VMManager.swift     Tart VM lifecycle + ~/.axon/vms.json registry
    └── CLI.swift           Argument parser
```

The library target (`AxonLib`) holds all logic and is `@testable import`-ed
from the unit tests. The `axon` executable target is a thin dispatch shim.

No external dependencies. Pure Swift with Cocoa and CoreGraphics. Swift Package Manager.
