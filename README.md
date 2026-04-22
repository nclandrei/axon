# axon

A macOS Accessibility CLI built so AI agents can drive native Mac apps reliably — over SSH, in a VM, or locally.

## Install

```bash
brew install nclandrei/tap/axon
```

Or grab the signed + notarized universal tarball from
[Releases](https://github.com/nclandrei/axon/releases) and drop the binary
anywhere on your `PATH`:

```bash
curl -L https://github.com/nclandrei/axon/releases/latest/download/axon-macos-universal.tar.gz \
  | tar -xz
chmod +x axon
mv axon /usr/local/bin/
```

Building from source is covered in [CONTRIBUTING.md](./CONTRIBUTING.md).

Requires macOS 14 (Sonoma) or later. axon needs Accessibility (and, for
`screenshot`, Screen Recording) permissions — run `axon doctor` after
installing and follow the fix hints.

## 60-second quickstart

```bash
axon doctor                                # confirm permissions are granted
axon launch --name TextEdit                # open an app
axon type --app TextEdit --path "AXWindow[0]/AXScrollArea[0]/AXTextArea[0]" --text "hello from axon"
axon screenshot --app TextEdit --output /tmp/textedit.png
axon close --app TextEdit --quit
```

That's the whole loop: launch, read, interact, verify, close. Every command
emits JSON on stdout and errors on stderr with non-zero exit codes, so
scripting from bash or an agent is the same shape either way.

## Testing your own Mac app

The recommended pattern is:

1. Give every interactive control a stable `accessibilityIdentifier` in your
   app source.
2. Drive it from a test script that calls `axon`.

`Samples/AxonSample/` is the canonical reference — a ~300-line SwiftUI notes
app with save/delete/close flows, an unsaved-changes sheet, and identifiers
on every control. The companion E2E test at
`Tests/AxonE2ETests/AxonSampleE2ETests.swift` shows the full arc: launch,
`wait-ready`, create a note, type, assert values, menu-driven save, sidebar
navigation, delete, quit-with-unsaved-changes, sheet dismissal. Read both
together to see how a test suite against a Mac app actually looks in axon.

A compact example:

```bash
axon launch --path ./Samples/AxonSample/.build/AxonSample.app
axon wait-ready --app AxonSample
axon click --app AxonSample --identifier newNoteButton
axon type  --app AxonSample --identifier noteTitleField --text "First note"
axon assert --app AxonSample --identifier noteTitleField --value "First note"
axon menu  --app AxonSample --path "File/Save"
axon close --app AxonSample --quit
```

See [CONTRIBUTING.md](./CONTRIBUTING.md#making-your-own-app-axon-testable)
for the identifier pattern in SwiftUI and AppKit.

## Commands

All commands output JSON on stdout; errors go to stderr with non-zero exit
codes. `axon --help` prints the full reference; `axon <command> --help`
prints per-command detail. The list below is a summary.

**App lifecycle**

| Command    | Purpose                                                |
| ---------- | ------------------------------------------------------ |
| `list`     | List running GUI apps                                  |
| `launch`   | Launch by `--name`, `--bundle-id`, or `--path`         |
| `activate` | Bring an app to the front                              |
| `close`    | Close a window or `--quit` the app                     |

**Inspection**

| Command       | Purpose                                                   |
| ------------- | --------------------------------------------------------- |
| `tree`        | Dump the AX tree as JSON (`--compact`, `--depth`)         |
| `get-value`   | Read `AXValue` off a target element                       |
| `focused`     | Which element currently has keyboard focus                |
| `window-info` | Window geometry, title, fullscreen state                  |
| `screenshot`  | PNG capture of a window or `--full-screen`, Retina-native |

**Interaction**

| Command            | Purpose                                             |
| ------------------ | --------------------------------------------------- |
| `click`            | Click a target element                              |
| `double-click`     | Double-click                                        |
| `right-click`      | Right-click (context menu)                          |
| `hover`            | Move the cursor onto the element                    |
| `drag`             | Drag from one target to another                     |
| `type`             | Type text into a field (`--clear` to replace)       |
| `set-value`        | Set `AXValue` directly                              |
| `key`              | Send a key or chord (e.g. `cmd+s`)                  |
| `scroll`           | Scroll within an element (`--direction`, `--amount`)|
| `menu`             | Drive an app's menu bar by path (`File/Save`)       |
| `move-resize`      | Move/resize a window                                |
| `clipboard`        | Read or write the pasteboard                        |

**Waits**

| Command          | Purpose                                                           |
| ---------------- | ----------------------------------------------------------------- |
| `wait`           | Wait for an element to appear / disappear (`--timeout`, polls 200ms) |
| `wait-ready`     | Wait until an app's AX tree is usable — replaces launch-then-sleep   |
| `wait-for-value` | Wait until an element's `AXValue` matches                         |

**Assertions**

| Command  | Purpose                                                                  |
| -------- | ------------------------------------------------------------------------ |
| `assert` | Hard assertion (`--exists`, `--value`, `--value-matches`, `--enabled`, `--focused`). Exit 0 pass, 1 fail, 2 lookup error. |
| `exists` | Soft check — always exits 0, returns `{ exists, count }`                 |

**Diagnostics**

| Command  | Purpose                                                              |
| -------- | -------------------------------------------------------------------- |
| `doctor` | Health check: AX trust, screen recording, binary signature, Tart, arch. Exit 0 if every required check passes. |

**VM lifecycle** (requires [Tart](https://github.com/cirruslabs/tart))

| Command       | Purpose                                                                          |
| ------------- | -------------------------------------------------------------------------------- |
| `vm-acquire`  | Clone + boot a base image, wait for IP, register in `~/.axon/vms.json`           |
| `vm-release`  | Stop + delete a VM by `--name`, or `--all` to release every registered VM        |
| `vm-list`     | List registered VMs (empty array, not an error, when none are acquired)          |

## Element targeting

Every interaction command accepts the same three targeting flags:

1. `--identifier <id>` — accessibility identifier (fastest, most stable,
   preferred).
2. `--label <text>` — exact title/label, then case-insensitive contains.
3. `--path <tree-path>` — structural address like
   `AXWindow[0]/AXGroup[1]/AXButton[0]`.

Two resolver shortcuts work anywhere a target is accepted:

- `--sheet` — the frontmost `AXSheet` attached to the active window.
- `--alert` — the frontmost alert sheet (role description "alert" or subrole
  `AXSystemDialog`).

Combine them with `--label` to target controls inside a modal:

```bash
axon click --app AxonSample --sheet --label "Don't Save"
```

When multiple elements match, enabled elements win.

## Error shape

Errors are structured JSON on stderr with context to help an agent
self-correct:

```json
{
  "error": "element_not_found",
  "message": "No element with identifier 'saveBtn' found in MyApp",
  "available": ["cancelBtn", "submitBtn", "AXButton:OK"]
}
```

## Known limitations

- **Electron / Flutter / Qt apps** often expose an empty or opaque AX tree.
  axon has no pixel or OCR fallback; it will report what AX reports, which
  for these frameworks is sometimes not much. Native AppKit and SwiftUI apps
  (with identifiers) are the happy path.
- **System modal and TCC permission dialogs** (the "X wants to access Y"
  prompts) live outside the AX API and cannot be dismissed by axon. Grant
  permissions ahead of time; `axon doctor` tells you what's missing.
- **Retrofitting closed third-party apps** that don't publish identifiers is
  possible via `--label` and `--path`, but expect fragility — the app can
  change both between releases.

## License

[MIT](./LICENSE).
