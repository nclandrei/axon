import Foundation
import Cocoa
import AxonLib

// MARK: - Help Text
// Single comprehensive help following the rodney/showboat pattern:
// everything in one --help output so AI agents get the full picture in one call.
// Per-subcommand --help kept for convenience with tighter formatting.

let helpMain = """
axon - macOS Accessibility CLI for AI agent workflows

Wraps Apple's AXUIElement API so AI agents can drive macOS apps over SSH.
All commands output JSON to stdout. Errors go to stderr with non-zero exit.

App discovery:
  axon list                                          List running GUI apps
  axon launch --name <name>                          Launch by app name
  axon launch --bundle-id <id>                       Launch by bundle identifier
  axon launch --path <path>                          Launch by .app bundle path

Inspection:
  axon tree --app <app> [--depth N] [--compact]      Dump accessibility tree as JSON
  axon screenshot --app <app> [--output <path>]      Capture window as PNG
  axon screenshot --app <app> --full-screen          Capture entire screen
  axon screenshot --app <app> --window <title>       Capture specific window

Interaction:
  axon click --app <app> <target>                    Click a UI element
  axon right-click --app <app> <target>              Right-click (context menu)
  axon double-click --app <app> <target>             Double-click an element
  axon type --app <app> <target> --text <str>        Type text into a field
  axon type --app <app> <target> --text <s> --clear  Replace existing field text
  axon scroll --app <app> <target> --direction <dir> Scroll within element
  axon key --app <app> --key <key> [--modifiers m]   Press a key with modifiers
  axon hover --app <app> <target>                    Move mouse to element
  axon drag --app <app> --from <t> --to <t>          Drag between elements

Window management:
  axon activate --app <app>                          Bring app to front
  axon close --app <app>                             Close frontmost window
  axon close --app <app> --window <title>            Close specific window
  axon close --app <app> --quit                      Quit the app entirely

Waiting:
  axon wait --app <app> <target> --appear            Wait for element to exist
  axon wait --app <app> <target> --disappear         Wait for element to vanish
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

Provide exactly one of --name, --bundle-id, or --path.
Waits up to 5 seconds for the app to start.

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

Activates app before clicking. Uses AXPress action.
Matching: identifier > exact label > case-insensitive contains. Prefers enabled elements.

  axon click --app MyApp --identifier saveButton
  axon click --app MyApp --label "Save"
  axon click --app MyApp --path "AXWindow[0]/AXGroup[0]/AXButton[2]"

Output:
  {"success": true, "element": {"role": "AXButton", "title": "Save", "identifier": "saveButton"}}

On failure, "available" lists nearby identifiers to help retry:
  {"error": "element_not_found", "message": "...", "available": ["cancelBtn", "submitBtn"]}
"""

let helpRightClick = """
axon right-click - Right-click a UI element (context menu)

  --app <name>        App name or bundle ID (required)
  --identifier <id>   Match by accessibility identifier
  --label <text>      Match by title or description
  --path <path>       Match by tree path (from 'axon tree')

Activates app before clicking. Tries AXShowMenu action first, falls back to
CGEvent right-click at the element center.

  axon right-click --app Finder --label "Documents"
  axon right-click --app MyApp --identifier fileItem
  axon right-click --app MyApp --path "AXWindow[0]/AXOutline[0]/AXRow[2]"

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

// MARK: - Help Dispatch

func showHelp(for command: String?) {
    let text: String
    switch command {
    case "list":       text = helpList
    case "launch":     text = helpLaunch
    case "tree":       text = helpTree
    case "click":       text = helpClick
    case "right-click": text = helpRightClick
    case "type":       text = helpType
    case "scroll":     text = helpScroll
    case "screenshot": text = helpScreenshot
    case "activate":   text = helpActivate
    case "close":      text = helpClose
    case "wait":       text = helpWait
    default:           text = helpMain
    }
    FileHandle.standardError.write(text.data(using: .utf8)!)
    FileHandle.standardError.write("\n".data(using: .utf8)!)
}

// MARK: - Main

let cli = CLI()

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

// Per-subcommand --help: `axon tree --help`
if cli.hasHelp() {
    showHelp(for: command)
    exit(0)
}

switch command {
case "list":
    let apps = listApps()
    printJSON(ListOutput(apps: apps))

case "launch":
    let name = cli.option("name")
    let bundleID = cli.option("bundle-id")
    let path = cli.option("path")

    if name == nil && bundleID == nil && path == nil {
        printError(code: "missing_option", message: "Provide --name, --bundle-id, or --path")
        exit(1)
    }

    if let app = launchApp(name: name, bundleID: bundleID, path: path) {
        printJSON(LaunchOutput(
            success: true,
            name: app.localizedName ?? name ?? "unknown",
            bundleID: app.bundleIdentifier,
            pid: app.processIdentifier
        ))
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

    if performClick(element: found.element) {
        printJSON(ClickOutput(
            success: true,
            element: ElementInfo(role: found.role, title: found.title, identifier: found.identifier)
        ))
    } else {
        printError(code: "click_failed", message: "AXPress action failed on element")
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

    if performRightClick(element: found.element) {
        printJSON(RightClickOutput(
            success: true,
            element: ElementInfo(role: found.role, title: found.title, identifier: found.identifier)
        ))
    } else {
        printError(code: "right_click_failed", message: "Right-click failed on element")
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
        printJSON(TypeOutput(success: true, method: method.rawValue))
    } else {
        printError(code: "type_failed", message: "Failed to set text on element via both direct and keyboard methods")
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
    printJSON(ScrollOutput(success: true))

case "screenshot":
    let appName = cli.requireOption("app")
    let outputPath = cli.option("output") ?? "/tmp/axon-screenshot.png"
    let fullScreen = cli.flag("full-screen")
    let windowTitle = cli.option("window")

    let (app, _) = resolveApp(name: appName)

    activateApp(app)
    usleep(200_000) // 200ms for window to be fully visible

    if let output = captureScreenshot(app: app, outputPath: outputPath, fullScreen: fullScreen, windowTitle: windowTitle) {
        printJSON(output)
    } else {
        exit(1)
    }

case "activate":
    let appName = cli.requireOption("app")
    let (app, _) = resolveApp(name: appName)

    let success = activateApp(app)
    printJSON(ActivateOutput(success: success))

case "close":
    let appName = cli.requireOption("app")
    let quit = cli.flag("quit")

    if quit {
        let (app, _) = resolveApp(name: appName)
        if quitApp(app) {
            printJSON(CloseOutput(success: true, action: "quit"))
        } else {
            printError(code: "quit_failed", message: "Failed to quit '\(appName)'. The app may have unsaved changes or blocked termination.")
            exit(1)
        }
    } else {
        checkAccessibilityPermission()
        let (_, axApp) = resolveApp(name: appName)
        let windowTitle = cli.option("window")
        if closeWindow(axApp: axApp, windowTitle: windowTitle) {
            printJSON(CloseOutput(success: true, action: "close_window"))
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
        printJSON(WaitOutput(success: true, elapsed_ms: elapsed))
    } else {
        let action = waitForAppear ? "appear" : "disappear"
        printError(code: "timeout", message: "Element did not \(action) within \(Int(timeout))s")
        exit(1)
    }

default:
    printError(code: "unknown_command", message: "Unknown command '\(command)'. Run 'axon --help' for usage.")
    exit(1)
}
