import Foundation
import Cocoa
import AxonLib

// MARK: - Help Text
// Single comprehensive help following the rodney/showboat pattern:
// everything in one --help output so AI agents get the full picture in one call.
// Per-subcommand --help kept for convenience with tighter formatting.

let helpMain = """
axon - macOS Accessibility CLI for AI agent workflows
  axon --version

Wraps Apple's AXUIElement API so AI agents can drive macOS apps over SSH.
All commands output JSON to stdout. Errors go to stderr with non-zero exit.
Use --format text for human-readable output instead of JSON.

App discovery:
  axon list                                          List running GUI apps
  axon launch --name <name>                          Launch by app name
  axon launch --bundle-id <id>                       Launch by bundle identifier
  axon launch --path <path>                          Launch by .app bundle path

Inspection:
  axon tree --app <app> [--depth N] [--compact]      Dump accessibility tree as JSON
  axon get-value --app <app> <target>                Read element value/state
  axon focused --app <app>                           Get focused element info
  axon window-info --app <app> [--window <title>]    Get window geometry
  axon screenshot --app <app> [--output <path>]      Capture window as PNG
  axon screenshot --app <app> --full-screen          Capture entire screen
  axon screenshot --app <app> --window <title>       Capture specific window

Interaction:
  axon click --app <app> <target> [--modifiers m]     Click a UI element
  axon right-click --app <app> <target> [--modifiers m]  Right-click (context menu)
  axon double-click --app <app> <target> [--modifiers m] Double-click an element
  axon type --app <app> <target> --text <str>        Type text into a field
  axon type --app <app> <target> --text <s> --clear  Replace existing field text
  axon scroll --app <app> <target> --direction <dir> Scroll within element
  axon key --app <app> --key <key> [--modifiers m]   Press a key with modifiers
  axon hover --app <app> <target>                    Move mouse to element
  axon drag --app <app> --from <t> --to <t>          Drag between elements
  axon menu --app <app> --path "File > Save"         Navigate and click menu item
  axon menu --app <app> --list                       List top-level menu items

Window management:
  axon activate --app <app>                          Bring app to front
  axon close --app <app>                             Close frontmost window
  axon close --app <app> --window <title>            Close specific window
  axon close --app <app> --quit                      Quit the app entirely
  axon move-resize --app <app> [--window <title>] [--x N] [--y N] [--width N] [--height N]

Clipboard:
  axon clipboard --get                               Read clipboard text
  axon clipboard --set --text <string>               Write text to clipboard

VM management (Tart):
  axon vm-acquire --base <image> [--headless] [--timeout <s>]   Clone+boot ephemeral VM
  axon vm-release --name <vm>                        Stop and delete a VM
  axon vm-release --all                              Stop and delete all axon VMs
  axon vm-list                                       List axon-managed VMs

Waiting:
  axon wait --app <app> <target> --appear            Wait for element to exist
  axon wait --app <app> <target> --disappear         Wait for element to vanish
  axon wait-for-value --app <app> <target> [--pattern <regex>]  Wait for value to change/match
  Add --timeout <seconds> to either (default: 10). Polls every 200ms.

Element targeting (<target> in click, type, scroll, wait):
  --identifier <id>   Accessibility identifier (exact match)
  --label <text>      Title or description (exact, then case-insensitive contains)
  --path <treepath>   Tree path from 'axon tree' output

  Priority: identifier > exact label > contains match. Prefers enabled elements.
  Use 'axon tree --compact' to discover identifiers and paths.

The --app flag accepts app names ("Finder") or bundle IDs ("com.apple.Finder").

Tree paths:
  Every node in 'axon tree' output has a "path" field like
  "AXWindow[0]/AXGroup[1]/AXButton[0]" that uniquely addresses it. Pass these
  to --path in click, type, scroll, and wait for precise targeting.

Type behavior:
  Tries direct AXValue attribute set first (instant, method: "direct"). Falls
  back to CGEvent keyboard injection if the field rejects direct set (method:
  "keyboard"). Use --clear to erase existing text before typing.

Screenshot options:
  --output <path>     Output path (default: /tmp/axon-screenshot.png)
  --full-screen       Capture entire screen instead of app window
  --window <title>    Capture a specific window by title

Scroll options:
  --direction <dir>   One of: up, down, left, right (required)
  --amount <N>        Lines to scroll (default: 3)

Exit codes:
  0  Success (JSON on stdout)
  1  Error (JSON on stderr: missing option, element not found, timeout)

Output format:
  Success: {"success": true, ...}
  Error:   {"error": "code", "message": "...", "available": [...]}

  The "available" field lists nearby element identifiers when a target isn't
  found, helping agents self-correct without re-reading the full tree.

Example — automate TextEdit:
  axon launch --name TextEdit
  axon tree --app TextEdit --compact                 # discover UI structure
  axon screenshot --app TextEdit                     # visually verify state
  axon type --app TextEdit --path "AXWindow[0]/AXScrollArea[0]/AXTextArea[0]" --text "Hello"
  axon click --app TextEdit --label Save
  axon wait --app TextEdit --label "Saved" --appear --timeout 5
  axon close --app TextEdit

Example — inspect and interact with Safari:
  axon list | jq '.[].name'                         # find running apps
  axon activate --app Safari                         # bring to front
  axon tree --app Safari --depth 3 --compact         # shallow tree scan
  axon click --app Safari --identifier "URL"
  axon type --app Safari --identifier "URL" --text "https://example.com" --clear
  axon screenshot --app Safari --output /tmp/safari.png

Run 'axon <command> --help' for per-command details.
"""

let helpList = """
axon list - List all running GUI apps

Returns JSON array of {name, bundleID, pid} for every app with a dock icon.

  axon list
  axon list | jq '.[].name'

Output:
  {"apps": [{"name": "Finder", "bundleID": "com.apple.finder", "pid": 512}, ...]}
"""

let helpLaunch = """
axon launch - Launch an app by name, bundle ID, or path

  --name <name>       App name (LaunchServices/Spotlight lookup)
  --bundle-id <id>    Bundle identifier (e.g. com.apple.TextEdit)
  --path <path>       Full path to .app bundle
  --timeout <seconds> Seconds to wait for app to start (default: 5)

Provide exactly one of --name, --bundle-id, or --path.

  axon launch --name TextEdit
  axon launch --bundle-id com.apple.Safari
  axon launch --path /Applications/Xcode.app

Output:
  {"success": true, "name": "TextEdit", "bundleID": "com.apple.TextEdit", "pid": 1234}
"""

let helpTree = """
axon tree - Dump the accessibility tree of an app as JSON

  --app <name>      App name or bundle ID (required)
  --depth <N>       Max tree depth (default: 15)
  --compact         Omit null fields and position/size

Every node includes a "path" field (e.g. "AXWindow[0]/AXGroup[1]/AXButton[0]")
that uniquely addresses it. Use these paths with --path in click, type, scroll, wait.

  axon tree --app Finder
  axon tree --app Finder --depth 3 --compact
  axon tree --app com.apple.Safari --compact

Output:
  {"app": "Finder", "pid": 512, "tree": {"role": "AXApplication", "path": "", "children": [...]}}
"""

let helpClick = """
axon click - Click a UI element

  --app <name>        App name or bundle ID (required)
  --identifier <id>   Match by accessibility identifier
  --label <text>      Match by title or description
  --path <path>       Match by tree path (from 'axon tree')
  --modifiers <mods>  Modifier keys: cmd, shift, alt, ctrl, fn (joined with +)

Activates app before clicking. Uses AXPress action (or CGEvent click when modifiers given).
Matching: identifier > exact label > case-insensitive contains. Prefers enabled elements.

  axon click --app MyApp --identifier saveButton
  axon click --app MyApp --label "Save"
  axon click --app MyApp --path "AXWindow[0]/AXGroup[0]/AXButton[2]"
  axon click --app Finder --label "file.txt" --modifiers shift

Output:
  {"success": true, "element": {"role": "AXButton", "title": "Save", "identifier": "saveButton"}}

On failure, "available" lists nearby identifiers to help retry:
  {"error": "element_not_found", "message": "...", "available": ["cancelBtn", "submitBtn"]}
"""

let helpHover = """
axon hover - Move the mouse cursor to an element

  --app <name>        App name or bundle ID (required)
  --identifier <id>   Match by accessibility identifier
  --label <text>      Match by title or description
  --path <path>       Match by tree path (from 'axon tree')

Activates app and moves the mouse to the center of the target element.
Useful for triggering hover states, tooltips, or preparing for other actions.

  axon hover --app Finder --label "Documents"
  axon hover --app MyApp --identifier menuItem
  axon hover --app MyApp --path "AXWindow[0]/AXButton[0]"

Output:
  {"success": true, "element": {...}, "position": {"x": 500.0, "y": 300.0}}
"""

let helpDrag = """
axon drag - Drag from one element to another

  --app <name>        App name or bundle ID (required)
  --from-identifier <id>    Source element by identifier
  --from-label <text>       Source element by label
  --from-path <path>        Source element by tree path
  --to-identifier <id>      Destination element by identifier
  --to-label <text>         Destination element by label
  --to-path <path>          Destination element by tree path
  --duration <seconds>      Drag duration in seconds (default: 0.5)

Performs a smooth mouse drag from the source to the destination element.

  axon drag --app Finder --from-label "file.txt" --to-label "Documents"

Output:
  {"success": true, "from": {"role": "AXCell", ...}, "to": {"role": "AXGroup", ...}}
"""

let helpKey = """
axon key - Press a key with optional modifiers

  --app <name>        App name or bundle ID (required)
  --key <name>        Key to press (required): return, tab, escape, space,
                      delete, up, down, left, right, f1-f12, a-z, 0-9, etc.
  --modifiers <mods>  Modifier keys separated by +: cmd, shift, alt, ctrl, fn

  axon key --app TextEdit --key c --modifiers cmd          # Copy
  axon key --app TextEdit --key v --modifiers cmd          # Paste
  axon key --app TextEdit --key z --modifiers cmd+shift    # Redo
  axon key --app TextEdit --key return                     # Enter
  axon key --app Finder --key a --modifiers cmd            # Select All

Output:
  {"success": true, "key": "c", "modifiers": ["cmd"]}
"""

let helpDoubleClick = """
axon double-click - Double-click a UI element

  --app <name>        App name or bundle ID (required)
  --identifier <id>   Match by accessibility identifier
  --label <text>      Match by title or description
  --path <path>       Match by tree path (from 'axon tree')
  --modifiers <mods>  Modifier keys: cmd, shift, alt, ctrl, fn (joined with +)

Activates app before clicking. Uses CGEvent double-click at element center.
Useful for opening files, selecting words, or triggering double-click actions.

  axon double-click --app Finder --label "Documents"
  axon double-click --app TextEdit --path "AXWindow[0]/AXScrollArea[0]/AXTextArea[0]"
  axon double-click --app Finder --label "file.txt" --modifiers shift

Output:
  {"success": true, "element": {"role": "AXStaticText", "title": "Documents", "identifier": null}}
"""

let helpRightClick = """
axon right-click - Right-click a UI element (context menu)

  --app <name>        App name or bundle ID (required)
  --identifier <id>   Match by accessibility identifier
  --label <text>      Match by title or description
  --path <path>       Match by tree path (from 'axon tree')
  --modifiers <mods>  Modifier keys: cmd, shift, alt, ctrl, fn (joined with +)

Activates app before clicking. Tries AXShowMenu action first, falls back to
CGEvent right-click at the element center. With modifiers, uses CGEvent directly.

  axon right-click --app Finder --label "Documents"
  axon right-click --app MyApp --identifier fileItem
  axon right-click --app MyApp --path "AXWindow[0]/AXOutline[0]/AXRow[2]"
  axon right-click --app Finder --label "file.txt" --modifiers shift

Output:
  {"success": true, "element": {"role": "AXRow", "title": "Documents", "identifier": null}}
"""

let helpType = """
axon type - Type text into a field

  --app <name>        App name or bundle ID (required)
  --identifier <id>   Match by accessibility identifier
  --label <text>      Match by title or description
  --path <path>       Match by tree path
  --text <string>     Text to enter (required)
  --clear             Clear existing text before typing

Tries direct AXValue set first (instant). Falls back to CGEvent keyboard injection.

  axon type --app TextEdit --path "AXWindow[0]/AXScrollArea[0]/AXTextArea[0]" --text "Hello world"
  axon type --app MyApp --identifier searchField --text "query" --clear
  axon type --app Safari --label "Address" --text "https://example.com" --clear

Output:
  {"success": true, "method": "direct"}    # or "keyboard" for fallback
"""

let helpScroll = """
axon scroll - Scroll within a UI element

  --app <name>        App name or bundle ID (required)
  --identifier <id>   Match by accessibility identifier
  --label <text>      Match by title or description
  --path <path>       Match by tree path
  --direction <dir>   One of: up, down, left, right (required)
  --amount <N>        Lines to scroll (default: 3)

Moves mouse to element center, then sends scroll wheel events.

  axon scroll --app Finder --identifier fileList --direction down
  axon scroll --app Safari --path "AXWindow[0]/AXScrollArea[0]" --direction down --amount 10

Output:
  {"success": true}
"""

let helpScreenshot = """
axon screenshot - Capture an app window or the full screen as PNG

  --app <name>        App name or bundle ID (required)
  --output <path>     Output path (default: /tmp/axon-screenshot.png)
  --full-screen       Capture entire screen instead of app window
  --window <title>    Capture a specific window by title

Activates app before capture. Captures at Retina resolution.

  axon screenshot --app Finder
  axon screenshot --app Xcode --output ~/Desktop/xcode.png
  axon screenshot --app Xcode --window "MyProject"
  axon screenshot --app Finder --full-screen

Output:
  {"success": true, "path": "/tmp/axon-screenshot.png", "width": 2560, "height": 1440}
"""

let helpActivate = """
axon activate - Bring an app to the front

  --app <name>        App name or bundle ID (required)

  axon activate --app Finder
  axon activate --app com.apple.Safari

Output:
  {"success": true}
"""

let helpClose = """
axon close - Close a window or quit an app

  --app <name>        App name or bundle ID (required)
  --window <title>    Close a specific window by title
  --quit              Quit the app entirely instead of closing a window

Without --quit: closes frontmost window (or --window match).
With --quit: sends terminate signal.

  axon close --app TextEdit                    # close frontmost window
  axon close --app Xcode --window "MyProject"  # close specific window
  axon close --app TextEdit --quit              # quit the app

Output:
  {"success": true, "action": "close_window"}    # or "quit"
"""

let helpWait = """
axon wait - Wait for a UI element to appear or disappear

  --app <name>        App name or bundle ID (required)
  --identifier <id>   Match by accessibility identifier
  --label <text>      Match by title or description
  --appear            Wait for element to exist (one required)
  --disappear         Wait for element to stop existing (one required)
  --timeout <N>       Timeout in seconds (default: 10)

Polls every 200ms. Use for async UI: loading spinners, sheets, alerts, confirmations.

  axon wait --app MyApp --identifier loadingSpinner --disappear --timeout 30
  axon wait --app MyApp --label "Welcome" --appear
  axon wait --app MyApp --label "Save complete" --appear --timeout 5

Output:
  {"success": true, "elapsed_ms": 1200}

On timeout:
  {"error": "timeout", "message": "Element did not appear within 10s"}
"""

let helpGetValue = """
axon get-value - Read the value/state of a UI element

  --app <name>        App name or bundle ID (required)
  --identifier <id>   Match by accessibility identifier
  --label <text>      Match by title or description
  --path <path>       Match by tree path (from 'axon tree')

Returns the element's role, value, title, selected text, enabled/focused/selected
state, and description. Useful for reading text fields, checkbox state, slider values.

  axon get-value --app TextEdit --path "AXWindow[0]/AXScrollArea[0]/AXTextArea[0]"
  axon get-value --app MyApp --identifier myCheckbox
  axon get-value --app MyApp --label "Volume"

Output:
  {"success": true, "role": "AXTextArea", "value": "Hello world", "title": null, ...}
"""

let helpFocused = """
axon focused - Get the currently focused element in an app

  --app <name>        App name or bundle ID (required)

Recursively searches the accessibility tree for the element with focus.
Returns its role, title, identifier, current value, and tree path.

  axon focused --app TextEdit
  axon focused --app Safari

Output:
  {"success": true, "element": {"role": "AXTextArea", ...}, "value": "text", "path": "AXWindow[0]/..."}
"""

let helpWindowInfo = """
axon window-info - Get window geometry and state

  --app <name>        App name or bundle ID (required)
  --window <title>    Filter by window title (optional)

Returns position, size, and state (main, minimized, full screen) for each window.
Without --window, returns info for all windows.

  axon window-info --app Finder
  axon window-info --app Xcode --window "MyProject"

Output:
  {"success": true, "windows": [{"title": "Finder", "position": {"x": 0, "y": 25}, ...}]}
"""

let helpMenu = """
axon menu - Navigate and activate a menu bar item

  --app <name>        App name or bundle ID (required)
  --path <menu-path>  Menu path like "File > Save" or "Edit > Find > Find..."
  --list              List top-level menu bar items instead of navigating

Use " > " (space-arrow-space) to separate menu levels.

  axon menu --app TextEdit --path "File > Save"
  axon menu --app Safari --path "Edit > Find > Find..."
  axon menu --app Finder --list

Output (--path):
  {"success": true, "menuItem": {"role": "AXMenuItem", "title": "Save", ...}}

Output (--list):
  {"success": true, "items": ["Apple", "Finder", "File", "Edit", ...]}
"""

let helpMoveResize = """
axon move-resize - Reposition or resize an app window

  --app <name>        App name or bundle ID (required)
  --window <title>    Target specific window by title (optional, defaults to frontmost)
  --x <N>             X position (pixels from left screen edge)
  --y <N>             Y position (pixels from top screen edge)
  --width <N>         Window width in pixels
  --height <N>        Window height in pixels

Provide any combination of --x, --y, --width, --height. Omitted dimensions keep
their current values. At least one dimension must be specified.

  axon move-resize --app Finder --x 100 --y 200
  axon move-resize --app Finder --width 800 --height 600
  axon move-resize --app TextEdit --x 0 --y 0 --width 1920 --height 1080
  axon move-resize --app Safari --window "GitHub" --x 50 --y 50

Output:
  {"success": true, "position": {"x": 100, "y": 200}, "size": {"width": 800, "height": 600}}
"""

let helpClipboard = """
axon clipboard - Read or write the system clipboard (pasteboard)

  --get               Read current clipboard text
  --set               Write text to clipboard (requires --text)
  --text <string>     Text to write (used with --set)

Provide exactly one of --get or --set.

  axon clipboard --get
  axon clipboard --set --text "Hello, world!"
  axon clipboard --get | jq -r '.text'

Output (get):
  {"success": true, "text": "clipboard contents here"}

Output (set):
  {"success": true, "text": null}
"""

let helpVMAcquire = """
axon vm-acquire - Clone, boot, and register an ephemeral macOS VM via Tart

  --base <image>      Base image to clone from (required, e.g. "sonoma-base"
                      or "ghcr.io/cirruslabs/macos-sonoma-base:latest")
  --headless          Boot the VM with --no-graphics (recommended for SSH)
  --timeout <N>       Seconds to wait for the VM to acquire an IP (default: 60)

Clones <base> via APFS COW (instant), starts the VM in the background, polls
'tart ip' until an address is available, and registers the VM in
~/.axon/vms.json. Requires Tart to be installed (brew install cirruslabs/cli/tart).

  axon vm-acquire --base sonoma-base --headless
  axon vm-acquire --base ghcr.io/cirruslabs/macos-sonoma-base:latest --timeout 120
  axon vm-acquire --base sequoia --headless --timeout 90

Output:
  {"success": true, "name": "axon-12ab34cd", "base": "sonoma-base",
   "created": "2026-04-11T10:30:00Z", "ip": "192.168.64.10"}

On failure (tart missing, clone error, IP timeout):
  {"error": "vm_acquire_failed", "message": "..."}
"""

let helpVMRelease = """
axon vm-release - Stop and delete an axon-managed VM

  --name <vm>         Name of the VM to release (returned by vm-acquire)
  --all               Release every VM currently in the registry

Provide exactly one of --name or --all. Stops the VM (ignores already-stopped),
deletes it via 'tart delete', and removes it from ~/.axon/vms.json.

  axon vm-release --name axon-12ab34cd
  axon vm-release --all

Output (--name):
  {"success": true, "name": "axon-12ab34cd"}

Output (--all):
  {"success": true, "released": 3, "failed": 0}

On failure (tart missing, delete error):
  {"error": "vm_release_failed", "message": "..."}
"""

let helpVMList = """
axon vm-list - List axon-managed VMs from the registry

Reads ~/.axon/vms.json and returns every VM acquired via 'axon vm-acquire'
that hasn't yet been released. Returns an empty list when the registry is
missing or empty (does not error).

  axon vm-list
  axon vm-list | jq '.vms[].ip'

Output:
  {"success": true, "vms": [
    {"name": "axon-12ab34cd", "base": "sonoma-base",
     "created": "2026-04-11T10:30:00Z", "ip": "192.168.64.10"},
    ...
  ]}
"""

let helpWaitForValue = """
axon wait-for-value - Wait until an element's value changes or matches a pattern

  --app <name>        App name or bundle ID (required)
  --identifier <id>   Match by accessibility identifier
  --label <text>      Match by title or description
  --path <path>       Match by tree path (from 'axon tree')
  --pattern <regex>   Wait until value matches this regex (optional)
  --timeout <N>       Timeout in seconds (default: 10)

Without --pattern: waits for the value to change from its initial state.
With --pattern: waits for the value to match the given regex.

Polls every 200ms. Element must exist at start (use 'wait --appear' first if needed).

  axon wait-for-value --app MyApp --identifier progress --timeout 30
  axon wait-for-value --app MyApp --identifier status --pattern "complete|done"
  axon wait-for-value --app MyApp --path "AXWindow[0]/AXTextField[0]" --pattern "^[0-9]+$"

Output:
  {"success": true, "elapsed_ms": 1200, "oldValue": "loading", "newValue": "complete"}

On timeout:
  {"error": "timeout", "message": "Value did not change within 10s"}
"""

// MARK: - Help Dispatch

func showHelp(for command: String?) {
    let text: String
    switch command {
    case "list":       text = helpList
    case "launch":     text = helpLaunch
    case "tree":       text = helpTree
    case "click":       text = helpClick
    case "double-click": text = helpDoubleClick
    case "right-click": text = helpRightClick
    case "hover":        text = helpHover
    case "drag":         text = helpDrag
    case "type":       text = helpType
    case "key":          text = helpKey
    case "scroll":     text = helpScroll
    case "screenshot": text = helpScreenshot
    case "activate":   text = helpActivate
    case "close":      text = helpClose
    case "wait":        text = helpWait
    case "get-value":   text = helpGetValue
    case "focused":     text = helpFocused
    case "window-info": text = helpWindowInfo
    case "menu":        text = helpMenu
    case "move-resize": text = helpMoveResize
    case "clipboard":  text = helpClipboard
    case "wait-for-value": text = helpWaitForValue
    case "vm-acquire":  text = helpVMAcquire
    case "vm-release":  text = helpVMRelease
    case "vm-list":     text = helpVMList
    default:            text = helpMain
    }
    FileHandle.standardError.write(text.data(using: .utf8)!)
    FileHandle.standardError.write("\n".data(using: .utf8)!)
}

// MARK: - Main

let cli = CLI()
let format = OutputFormat(rawValue: cli.option("format") ?? "json") ?? .json

/// Shared ISO8601 formatter for serializing VM `Date` fields as JSON strings.
let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

func emit<T: Encodable>(_ value: T, plain: [(String, String)]) {
    if format == .text {
        printPlain(plain)
    } else {
        printJSON(value)
    }
}

guard let command = cli.command else {
    showHelp(for: nil)
    exit(1)
}

// Global --help: `axon --help` or `axon help`
if command == "--help" || command == "-h" || command == "help" {
    // Check if there's a subcommand after help: `axon help tree`
    let subcommand = cli.args.count > 1 ? cli.args[1] : nil
    showHelp(for: subcommand)
    exit(0)
}

if command == "--version" || command == "-V" {
    print(axonVersion)
    exit(0)
}

// Per-subcommand --help: `axon tree --help`
if cli.hasHelp() {
    showHelp(for: command)
    exit(0)
}

switch command {
case "list":
    let apps = listApps()
    let listOut = ListOutput(apps: apps)
    if format == .text {
        for app in apps {
            print("\(app.name)  \(app.bundleID ?? "-")  pid:\(app.pid)")
        }
    } else {
        printJSON(listOut)
    }

case "launch":
    let name = cli.option("name")
    let bundleID = cli.option("bundle-id")
    let path = cli.option("path")

    let timeout = TimeInterval(cli.intOption("timeout", default: 5))

    if name == nil && bundleID == nil && path == nil {
        printError(code: "missing_option", message: "Provide --name, --bundle-id, or --path")
        exit(1)
    }

    if let app = launchApp(name: name, bundleID: bundleID, path: path, timeout: timeout) {
        let launchOut = LaunchOutput(
            success: true,
            name: app.localizedName ?? name ?? "unknown",
            bundleID: app.bundleIdentifier,
            pid: app.processIdentifier
        )
        emit(launchOut, plain: [
            ("name", launchOut.name),
            ("bundleID", launchOut.bundleID ?? "-"),
            ("pid", String(launchOut.pid)),
        ])
    } else {
        let target = name ?? bundleID ?? path ?? "unknown"
        printError(code: "launch_failed", message: "Failed to launch '\(target)'. Check that the app exists and the name/bundle ID is correct.")
        exit(1)
    }

case "tree":
    checkAccessibilityPermission()
    let appName = cli.requireOption("app")
    let maxDepth = cli.intOption("depth", default: 15)
    let compact = cli.flag("compact")

    let (app, axApp) = resolveApp(name: appName)

    let tree = buildTree(element: axApp, depth: 0, maxDepth: maxDepth, path: "")

    if compact {
        printJSON(CompactTreeOutput(app: app.localizedName ?? appName, pid: app.processIdentifier, tree: tree.compacted()))
    } else {
        printJSON(TreeOutput(app: app.localizedName ?? appName, pid: app.processIdentifier, tree: tree))
    }

case "click":
    checkAccessibilityPermission()
    let appName = cli.requireOption("app")
    let (app, axApp) = resolveApp(name: appName)

    activateApp(app)

    let found = resolveElement(
        appElement: axApp,
        identifier: cli.option("identifier"),
        label: cli.option("label"),
        path: cli.option("path"),
        appName: appName
    )

    let modifierStr = cli.option("modifiers")
    let flags = modifierStr.map { parseModifiers($0) } ?? CGEventFlags()
    let modList: [String]? = modifierStr?.lowercased().split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }

    if performClick(element: found.element, modifiers: flags) {
        let clickOut = ClickOutput(
            success: true,
            element: ElementInfo(role: found.role, title: found.title, identifier: found.identifier),
            modifiers: modList
        )
        emit(clickOut, plain: [
            ("clicked", [found.role, found.title, found.identifier].compactMap { $0 }.joined(separator: " ")),
        ])
    } else {
        printError(code: "click_failed", message: "AXPress action failed on element")
        exit(1)
    }

case "double-click":
    checkAccessibilityPermission()
    let appName = cli.requireOption("app")
    let (app, axApp) = resolveApp(name: appName)

    activateApp(app)

    let found = resolveElement(
        appElement: axApp,
        identifier: cli.option("identifier"),
        label: cli.option("label"),
        path: cli.option("path"),
        appName: appName
    )

    let modifierStr = cli.option("modifiers")
    let flags = modifierStr.map { parseModifiers($0) } ?? CGEventFlags()
    let modList: [String]? = modifierStr?.lowercased().split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }

    if performDoubleClick(element: found.element, modifiers: flags) {
        let dcOut = DoubleClickOutput(
            success: true,
            element: ElementInfo(role: found.role, title: found.title, identifier: found.identifier),
            modifiers: modList
        )
        emit(dcOut, plain: [
            ("double-clicked", [found.role, found.title, found.identifier].compactMap { $0 }.joined(separator: " ")),
        ])
    } else {
        printError(code: "double_click_failed", message: "Double-click failed on element")
        exit(1)
    }

case "right-click":
    checkAccessibilityPermission()
    let appName = cli.requireOption("app")
    let (app, axApp) = resolveApp(name: appName)

    activateApp(app)

    let found = resolveElement(
        appElement: axApp,
        identifier: cli.option("identifier"),
        label: cli.option("label"),
        path: cli.option("path"),
        appName: appName
    )

    let modifierStr = cli.option("modifiers")
    let flags = modifierStr.map { parseModifiers($0) } ?? CGEventFlags()
    let modList: [String]? = modifierStr?.lowercased().split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }

    if performRightClick(element: found.element, modifiers: flags) {
        let rcOut = RightClickOutput(
            success: true,
            element: ElementInfo(role: found.role, title: found.title, identifier: found.identifier),
            modifiers: modList
        )
        emit(rcOut, plain: [
            ("right-clicked", [found.role, found.title, found.identifier].compactMap { $0 }.joined(separator: " ")),
        ])
    } else {
        printError(code: "right_click_failed", message: "Right-click failed on element")
        exit(1)
    }

case "hover":
    checkAccessibilityPermission()
    let appName = cli.requireOption("app")
    let (app, axApp) = resolveApp(name: appName)

    activateApp(app)

    let found = resolveElement(
        appElement: axApp,
        identifier: cli.option("identifier"),
        label: cli.option("label"),
        path: cli.option("path"),
        appName: appName
    )

    if let position = performHover(element: found.element) {
        let hoverOut = HoverOutput(
            success: true,
            element: ElementInfo(role: found.role, title: found.title, identifier: found.identifier),
            position: position
        )
        emit(hoverOut, plain: [
            ("hovered", [found.role, found.title, found.identifier].compactMap { $0 }.joined(separator: " ")),
            ("position", "\(position.x), \(position.y)"),
        ])
    } else {
        printError(code: "hover_failed", message: "Could not determine element position for hover")
        exit(1)
    }

case "drag":
    checkAccessibilityPermission()
    let appName = cli.requireOption("app")
    let (app, axApp) = resolveApp(name: appName)

    activateApp(app)

    let fromId = cli.option("from-identifier")
    let fromLabel = cli.option("from-label")
    let fromPath = cli.option("from-path")
    if fromId == nil && fromLabel == nil && fromPath == nil {
        printError(code: "missing_option", message: "Provide --from-identifier, --from-label, or --from-path for source element")
        exit(1)
    }
    let fromFound = resolveElement(appElement: axApp, identifier: fromId, label: fromLabel, path: fromPath, appName: appName)

    let toId = cli.option("to-identifier")
    let toLabel = cli.option("to-label")
    let toPath = cli.option("to-path")
    if toId == nil && toLabel == nil && toPath == nil {
        printError(code: "missing_option", message: "Provide --to-identifier, --to-label, or --to-path for destination element")
        exit(1)
    }
    let toFound = resolveElement(appElement: axApp, identifier: toId, label: toLabel, path: toPath, appName: appName)

    let duration = cli.doubleOption("duration") ?? 0.5

    if performDrag(fromElement: fromFound.element, toElement: toFound.element, duration: duration) {
        let dragOut = DragOutput(
            success: true,
            from: ElementInfo(role: fromFound.role, title: fromFound.title, identifier: fromFound.identifier),
            to: ElementInfo(role: toFound.role, title: toFound.title, identifier: toFound.identifier)
        )
        emit(dragOut, plain: [
            ("dragged", "from \(fromFound.title ?? fromFound.role ?? "element") to \(toFound.title ?? toFound.role ?? "element")"),
        ])
    } else {
        printError(code: "drag_failed", message: "Drag failed — could not determine element positions")
        exit(1)
    }

case "type":
    checkAccessibilityPermission()
    let appName = cli.requireOption("app")
    let text = cli.requireOption("text")
    let clear = cli.flag("clear")
    let (app, axApp) = resolveApp(name: appName)

    activateApp(app)

    let found = resolveElement(
        appElement: axApp,
        identifier: cli.option("identifier"),
        label: cli.option("label"),
        path: cli.option("path"),
        appName: appName
    )

    if let method = performType(element: found.element, text: text, clear: clear) {
        let typeOut = TypeOutput(success: true, method: method.rawValue)
        emit(typeOut, plain: [("typed", "ok"), ("method", method.rawValue)])
    } else {
        printError(code: "type_failed", message: "Failed to set text on element via both direct and keyboard methods")
        exit(1)
    }

case "key":
    let appName = cli.requireOption("app")
    let keyName = cli.requireOption("key")
    let (app, _) = resolveApp(name: appName)

    activateApp(app)

    let modifierStr = cli.option("modifiers")
    let flags = modifierStr.map { parseModifiers($0) } ?? CGEventFlags()
    let modList: [String]? = modifierStr?.lowercased().split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }

    if performKeyPress(keyName: keyName, modifiers: flags) {
        let keyOut = KeyOutput(success: true, key: keyName.lowercased(), modifiers: modList)
        emit(keyOut, plain: [
            ("key", keyName.lowercased()),
            ("modifiers", modList?.joined(separator: "+") ?? "none"),
        ])
    } else {
        let available = Array(keyNameToCode.keys.sorted())
        printError(code: "invalid_key", message: "Unknown key '\(keyName)'. See 'axon key --help' for available key names.", available: available)
        exit(1)
    }

case "scroll":
    checkAccessibilityPermission()
    let appName = cli.requireOption("app")
    let dirStr = cli.requireOption("direction")
    let amount = Int32(cli.intOption("amount", default: 3))
    let (app, axApp) = resolveApp(name: appName)

    guard let direction = ScrollDirection(rawValue: dirStr) else {
        printError(code: "invalid_direction", message: "Direction must be one of: up, down, left, right")
        exit(1)
    }

    activateApp(app)

    let found = resolveElement(
        appElement: axApp,
        identifier: cli.option("identifier"),
        label: cli.option("label"),
        path: cli.option("path"),
        appName: appName
    )

    performScroll(element: found.element, direction: direction, amount: amount)
    emit(ScrollOutput(success: true), plain: [("scrolled", "\(direction.rawValue) \(amount)")])

case "screenshot":
    let appName = cli.requireOption("app")
    let outputPath = cli.option("output") ?? "/tmp/axon-screenshot.png"
    let fullScreen = cli.flag("full-screen")
    let windowTitle = cli.option("window")

    let (app, _) = resolveApp(name: appName)

    activateApp(app)
    usleep(200_000) // 200ms for window to be fully visible

    if let ssOutput = captureScreenshot(app: app, outputPath: outputPath, fullScreen: fullScreen, windowTitle: windowTitle) {
        emit(ssOutput, plain: [
            ("path", ssOutput.path),
            ("size", "\(ssOutput.width)x\(ssOutput.height)"),
        ])
    } else {
        exit(1)
    }

case "activate":
    let appName = cli.requireOption("app")
    let (app, _) = resolveApp(name: appName)

    let success = activateApp(app)
    emit(ActivateOutput(success: success), plain: [("activated", success ? "yes" : "no")])

case "close":
    let appName = cli.requireOption("app")
    let quit = cli.flag("quit")

    if quit {
        let (app, _) = resolveApp(name: appName)
        if quitApp(app) {
            emit(CloseOutput(success: true, action: "quit"), plain: [("closed", "quit")])
        } else {
            printError(code: "quit_failed", message: "Failed to quit '\(appName)'. The app may have unsaved changes or blocked termination.")
            exit(1)
        }
    } else {
        checkAccessibilityPermission()
        let (_, axApp) = resolveApp(name: appName)
        let windowTitle = cli.option("window")
        if closeWindow(axApp: axApp, windowTitle: windowTitle) {
            emit(CloseOutput(success: true, action: "close_window"), plain: [("closed", "close_window")])
        } else {
            let detail = windowTitle != nil ? "window '\(windowTitle!)'" : "frontmost window"
            printError(code: "close_failed", message: "Failed to close \(detail) of '\(appName)'")
            exit(1)
        }
    }

case "wait":
    checkAccessibilityPermission()
    let appName = cli.requireOption("app")
    let timeout = TimeInterval(cli.intOption("timeout", default: 10))
    let appear = cli.flag("appear")
    let disappear = cli.flag("disappear")

    if !appear && !disappear {
        printError(code: "missing_option", message: "Provide --appear or --disappear")
        exit(1)
    }

    let (_, axApp) = resolveApp(name: appName)

    let selector: ElementSelector
    if let id = cli.option("identifier") {
        selector = .identifier(id)
    } else if let lbl = cli.option("label") {
        selector = .label(lbl)
    } else {
        printError(code: "missing_selector", message: "Provide --identifier or --label for wait")
        exit(1)
    }

    let waitForAppear = appear

    if let elapsed = performWait(appElement: axApp, selector: selector, appear: waitForAppear, timeout: timeout) {
        emit(WaitOutput(success: true, elapsed_ms: elapsed), plain: [("waited", "\(elapsed)ms")])
    } else {
        let action = waitForAppear ? "appear" : "disappear"
        printError(code: "timeout", message: "Element did not \(action) within \(Int(timeout))s")
        exit(1)
    }

case "get-value":
    checkAccessibilityPermission()
    let appName = cli.requireOption("app")
    let (app, axApp) = resolveApp(name: appName)

    activateApp(app)

    let found = resolveElement(
        appElement: axApp,
        identifier: cli.option("identifier"),
        label: cli.option("label"),
        path: cli.option("path"),
        appName: appName
    )

    let output = getElementValue(element: found.element)
    printJSON(output)

case "focused":
    checkAccessibilityPermission()
    let appName = cli.requireOption("app")
    let (_, axApp) = resolveApp(name: appName)

    if let result = findFocusedElement(root: axApp, path: "") {
        printJSON(FocusedOutput(
            success: true,
            element: ElementInfo(role: result.role, title: result.title, identifier: result.identifier),
            value: result.value,
            path: result.path
        ))
    } else {
        printJSON(FocusedOutput(success: true, element: nil, value: nil, path: nil))
    }

case "window-info":
    checkAccessibilityPermission()
    let appName = cli.requireOption("app")
    let (_, axApp) = resolveApp(name: appName)
    let windowTitle = cli.option("window")

    let windows = getWindowInfo(axApp: axApp, windowTitle: windowTitle)
    printJSON(WindowInfoOutput(success: true, windows: windows))

case "menu":
    checkAccessibilityPermission()
    let appName = cli.requireOption("app")
    let (app, axApp) = resolveApp(name: appName)
    let list = cli.flag("list")

    if list {
        let items = listMenuBarItems(axApp: axApp)
        printJSON(MenuListOutput(success: true, items: items))
    } else {
        let menuPath = cli.requireOption("path")

        activateApp(app)

        if let found = performMenuAction(axApp: axApp, menuPath: menuPath) {
            printJSON(MenuOutput(
                success: true,
                menuItem: ElementInfo(role: found.role, title: found.title, identifier: found.identifier)
            ))
        } else {
            let topItems = listMenuBarItems(axApp: axApp)
            printError(
                code: "menu_not_found",
                message: "Could not find menu item at path '\(menuPath)'",
                available: topItems
            )
            exit(1)
        }
    }

case "move-resize":
    checkAccessibilityPermission()
    let appName = cli.requireOption("app")
    let (app, axApp) = resolveApp(name: appName)
    let windowTitle = cli.option("window")

    let x = cli.doubleOption("x")
    let y = cli.doubleOption("y")
    let width = cli.doubleOption("width")
    let height = cli.doubleOption("height")

    if x == nil && y == nil && width == nil && height == nil {
        printError(code: "missing_option", message: "Provide at least one of --x, --y, --width, --height")
        exit(1)
    }

    activateApp(app)

    let windows: [AXUIElement] = axAttribute(axApp, kAXWindowsAttribute as String) ?? []
    let targetWindow: AXUIElement?
    if let title = windowTitle {
        targetWindow = windows.first { win in
            let t: String? = axStringAttribute(win, kAXTitleAttribute as String)
            return t?.localizedCaseInsensitiveContains(title) == true
        }
    } else {
        targetWindow = windows.first
    }

    guard let window = targetWindow else {
        let detail = windowTitle != nil ? "window '\(windowTitle!)'" : "frontmost window"
        printError(code: "window_not_found", message: "No \(detail) found for '\(appName)'")
        exit(1)
    }

    let result = performMoveResize(window: window, x: x, y: y, width: width, height: height)
    let success = result.positionSet || result.sizeSet
    printJSON(MoveResizeOutput(success: success, position: result.newPosition, size: result.newSize))
    if !success { exit(1) }

case "clipboard":
    let isGet = cli.flag("get")
    let isSet = cli.flag("set")

    if !isGet && !isSet {
        printError(code: "missing_option", message: "Provide --get or --set")
        exit(1)
    }

    if isGet {
        let text = getClipboard()
        printJSON(ClipboardOutput(success: true, text: text))
    } else {
        let text = cli.requireOption("text")
        let success = setClipboard(text: text)
        printJSON(ClipboardOutput(success: success, text: nil))
        if !success { exit(1) }
    }

case "wait-for-value":
    checkAccessibilityPermission()
    let appName = cli.requireOption("app")
    let timeout = TimeInterval(cli.intOption("timeout", default: 10))
    let pattern = cli.option("pattern")

    let (_, axApp) = resolveApp(name: appName)

    let selector: ElementSelector
    if let id = cli.option("identifier") {
        selector = .identifier(id)
    } else if let lbl = cli.option("label") {
        selector = .label(lbl)
    } else if let p = cli.option("path") {
        selector = .path(p)
    } else {
        printError(code: "missing_selector", message: "Provide --identifier, --label, or --path")
        exit(1)
    }

    if let result = performWaitForValue(appElement: axApp, selector: selector, pattern: pattern, timeout: timeout) {
        printJSON(WaitForValueOutput(success: true, elapsed_ms: result.elapsed_ms, oldValue: result.oldValue, newValue: result.newValue))
    } else {
        let desc = pattern != nil ? "Value did not match pattern '\(pattern!)' within \(Int(timeout))s" : "Value did not change within \(Int(timeout))s"
        printError(code: "timeout", message: desc)
        exit(1)
    }

case "vm-acquire":
    let base = cli.requireOption("base")
    let headless = cli.flag("headless")
    let timeout = cli.intOption("timeout", default: 60)

    switch vmAcquire(base: base, headless: headless, timeout: timeout) {
    case .success(let entry):
        let createdStr = isoFormatter.string(from: entry.created)
        let out = VMAcquireOutput(
            success: true,
            name: entry.name,
            base: entry.base,
            created: createdStr,
            ip: entry.ip
        )
        emit(out, plain: [
            ("name", entry.name),
            ("base", entry.base),
            ("ip", entry.ip ?? "-"),
            ("created", createdStr),
        ])
    case .failure(let err):
        printError(code: "vm_acquire_failed", message: err.description)
        exit(1)
    }

case "vm-release":
    let all = cli.flag("all")
    let name = cli.option("name")

    if !all && name == nil {
        printError(code: "missing_option", message: "Provide --name <vm> or --all")
        exit(1)
    }

    if all {
        let counts = vmReleaseAll()
        let out = VMReleaseAllOutput(
            success: counts.failed == 0,
            released: counts.released,
            failed: counts.failed
        )
        emit(out, plain: [
            ("released", String(counts.released)),
            ("failed", String(counts.failed)),
        ])
        if counts.failed > 0 { exit(1) }
    } else {
        // name is non-nil here because we returned early above
        let vmName = name!
        switch vmRelease(name: vmName) {
        case .success:
            let out = VMReleaseOutput(success: true, name: vmName)
            emit(out, plain: [("released", vmName)])
        case .failure(let err):
            printError(code: "vm_release_failed", message: err.description)
            exit(1)
        }
    }

case "vm-list":
    let entries = vmListEntries()
    let infos = entries.map { entry in
        VMInfo(
            name: entry.name,
            base: entry.base,
            created: isoFormatter.string(from: entry.created),
            ip: entry.ip
        )
    }
    let out = VMListOutput(success: true, vms: infos)
    if format == .text {
        for info in infos {
            print("\(info.name)  \(info.base)  \(info.ip ?? "-")  \(info.created)")
        }
    } else {
        printJSON(out)
    }

default:
    printError(code: "unknown_command", message: "Unknown command '\(command)'. Run 'axon --help' for usage.")
    exit(1)
}
