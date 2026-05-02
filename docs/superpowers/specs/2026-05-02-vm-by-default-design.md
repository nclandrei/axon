# axon: VM-by-default routing

**Status:** approved
**Date:** 2026-05-02
**Author:** Andrei Nicolae (with Claude Opus 4.7)

## Problem

`axon` was designed to be installed both on a host *and* inside a Tart VM, with the
intent that agents SSH into the VM and run UI commands there. In practice agents
install axon on their host, type `axon click --app Cicero`, and unintentionally
drive the host's running Cicero — stealing focus, mutating real state, and
defeating the isolation Tart was supposed to provide.

The redesign: **UI-driving commands route to a per-app Tart VM by default.**
Driving the host becomes the explicit opt-out (`--local` / `AXON_TARGET=local`).

## Design decisions (settled in brainstorming)

1. **Execution model: reuse-or-acquire.** Each invocation looks up the registry
   for a running VM whose base matches the requested app's bundle ID. If one
   exists, dispatch into it. Otherwise `vm-acquire` a fresh clone, register it,
   dispatch. The user explicitly tears down via `axon vm-release --all`.
2. **App → base mapping via bundle ID.** `axon vm-bake` gains a
   `--for-bundle <id>` flag that records the bundle ID alongside the base name.
   `axon list`-equivalent resolution at dispatch time looks up the running
   app's bundle ID against the bake registry.
3. **App provisioning is the user's job.** axon does not auto-ship app builds.
   A new explicit `axon vm-sync --app <name> --path <build>` verb rsyncs an
   updated build into running VMs registered for that bundle ID. No automatic
   sync on `vm-acquire`.
4. **Escape hatches: `--local` and `AXON_TARGET=local`.** `--local` per-call;
   env applies process-wide; flag overrides env. **Hard error** when no base
   mapping exists for the requested bundle ID; no silent host fallback.
5. **Transport: SSH dispatch with baked-in axon.** Host shells out to
   `ssh admin@<vm-ip> AXON_TARGET=local axon <argv...>`. The VM must already
   have an `axon` binary on `PATH` — installing it is part of the
   one-time `vm-bake` setup, documented in README.
6. **File outputs cross the boundary via auto-scp.** `--output /host/path` in
   VM mode is rewritten to a VM-side temp path; after SSH dispatch returns,
   axon scps the temp file back and deletes the VM-side copy.

## Architecture

A new file `Sources/AxonLib/Router.swift` owns target resolution and SSH
dispatch. The flow added to `Sources/axon/main.swift`, before the existing
command switch:

```
argv → classifyCommand(command)            // .vmRoutable | .alwaysLocal
     → resolveTarget(argv, command)         // .local | .remote(VMEntry)
     → if .remote:
           remapFileOutputs(argv)            // --output /host → --output /tmp/xxx + ScpBack
           sshDispatch(vm, rewrittenArgv)    // ssh admin@ip AXON_TARGET=local axon …
           applyScpBacks(plan)               // pull files back to host
           passThroughExitAndJSON()
        else:
           // unchanged: fall through to existing switch
```

Three pure functions, each unit-testable without SSH or a VM:

- `classifyCommand(_:) -> CommandClass` — table lookup.
- `resolveTarget(argv:command:registry:env:) -> Target` — applies `--local`,
  `AXON_TARGET`, `--vm <name>`, `--app <name>` → bundle-ID → registry; returns
  `.local`, `.remote(VMEntry)`, or throws a typed `RouterError`.
- `remapFileOutputs(argv:command:) -> (rewrittenArgv, [ScpBack])` — only
  `screenshot --output` today; isolated per-command rules so future commands
  can opt in.

`sshDispatch` is the only impure piece; tests stub it via a `SSHDispatcher`
protocol.

## Command classification

| Class | Commands |
|---|---|
| `.vmRoutable` | list, launch, tree, click, double-click, right-click, hover, drag, type, key, scroll, screenshot, activate, close, wait, get-value, focused, window-info, menu, set-value, move-resize, clipboard, wait-ready, wait-for-value, assert, exists |
| `.alwaysLocal` | vm-bake, vm-acquire, vm-release, vm-list, vm-sync, doctor |

Note: `list`, `focused`, and `clipboard` have no `--app` argument. In VM mode
they require explicit `--vm <name>` or `--local`. Without either, axon errors
with `missing_target` and the message tells the user how to disambiguate.

## Data model changes

### Registry schema (`~/.axon/vms.json`)

`VMEntry` is unchanged. A new top-level `bases` map records bundle-ID → base
mapping populated by `vm-bake --for-bundle`:

```json
{
  "vms": [...existing...],
  "bases": [
    {
      "name": "axon-cicero-base",
      "source": "ghcr.io/cirruslabs/macos-sequoia-base:latest",
      "bundleID": "com.andreinicolas.Cicero",
      "displayName": "Cicero",
      "baked": "2026-05-02T19:30:00Z"
    }
  ]
}
```

`vm-bake` without `--for-bundle` works as today (no bundle mapping recorded;
the base is usable only via explicit `--base` to `vm-acquire`).

`displayName` is recorded at bake time (from the host's `NSWorkspace` lookup
of the bundle ID, when available; otherwise omitted) so dispatch-time
resolution of `--app <name>` works even when the app is not installed on
the host.

### New types in `AxonLib`

```swift
public enum CommandClass { case vmRoutable, alwaysLocal }

public enum Target {
    case local
    case remote(VMEntry)
}

public enum RouterError: Error {
    case noBaseRegistered(bundleID: String)
    case missingTarget(command: String)              // list/focused/clipboard with no --app/--vm/--local
    case bundleIDNotResolvable(appName: String)
    case vmNotFound(name: String)
    case vmNotReady(name: String)
    case sshFailed(stderr: String, exitCode: Int32)
}

// resolveTarget throws RouterError or returns Target.
// classifyCommand and remapFileOutputs are total functions.

public struct ScpBack {
    public let vmPath: String      // /tmp/axon-out-xxxx.png inside VM
    public let hostPath: String    // user's --output value
}

public protocol SSHDispatcher {
    func run(vmIP: String, argv: [String], env: [String: String])
        -> (stdout: Data, stderr: Data, exitCode: Int32)
}
```

## Command flow

### Happy path: `axon click --app Cicero --label Save` on host

1. `main.swift` parses argv, sees `command == "click"`.
2. `classifyCommand("click") == .vmRoutable`.
3. `resolveTarget`:
   - `--local` not set; `AXON_TARGET` not `local`.
   - `--vm` not set.
   - `--app Cicero` → resolve to a bundle ID. Lookup order:
     1. `bases[].displayName` case-insensitive match (works without app on host)
     2. host `NSWorkspace` lookup for an installed/running app named "Cicero"
     3. fail with `bundleIDNotResolvable`
     If `--bundle-id <id>` is passed instead, skip resolution and use it
     directly. Then look up the bundle ID in the `bases` map.
   - Found `axon-cicero-base`. Check `vms[]` for an entry with
     `base == "axon-cicero-base"`. If found, return `.remote(entry)`. Else
     call `vmAcquire(base: "axon-cicero-base", headless: true, timeout: 60)`,
     register the result, return `.remote(newEntry)`.
4. `remapFileOutputs`: no `--output`, no rewrites.
5. `sshDispatch`: runs `ssh admin@<ip> AXON_TARGET=local axon click --app Cicero --label Save`.
6. Stdout streamed back verbatim (JSON pass-through). Exit code propagated.

### Screenshot with `--output`

Same flow through step 4. `remapFileOutputs` rewrites
`--output /Users/me/shot.png` to `--output /tmp/axon-out-<uuid>.png` and
records a `ScpBack`. After `sshDispatch`, `applyScpBacks` runs
`scp admin@<ip>:/tmp/axon-out-<uuid>.png /Users/me/shot.png`, then
`ssh admin@<ip> rm /tmp/axon-out-<uuid>.png`. JSON output's `path` field is
post-processed to show the host path, not the VM path, so callers see what
they expect.

### Hard-error path: no base baked

`axon click --app Cicero ...`, but `bases` has no entry for
`com.andreinicolas.Cicero`. `resolveTarget` throws
`.noBaseRegistered(bundleID:)`. `main.swift` prints:

```
error: no_base_registered
message: No VM base registered for com.andreinicolas.Cicero.
hint: Bake one with: axon vm-bake --source <image> --name axon-cicero-base --for-bundle com.andreinicolas.Cicero
      Or pass --local to drive the host (not recommended for tests).
```

Exit 2.

## CLI surface changes

### New / changed flags on every `.vmRoutable` command

- `--local` — force host execution. Wins over env. No-op if already host.
- `--vm <name>` — target a specific registered VM by name. Skips bundle-ID
  resolution. Errors if the VM isn't in the registry or has no IP.

### New env var

- `AXON_TARGET=local` — process-wide default of "drive the host." Used by
  axon's own E2E tests so they keep targeting the host's TextEdit/Finder.

### Changed commands

- `vm-bake`: gains `--for-bundle <id>` (optional). Without it, no bundle
  mapping is written; the base is usable only via explicit `--base`.

### New command

- `vm-sync --app <name> --path <build-dir>` — rsync a freshly built `.app`
  into every running VM whose base matches the app's bundle ID. Pure
  convenience for in-development apps; unrelated to routing. Implementation
  is a thin wrapper around `rsync -e ssh`.

## Error handling

| Error | Code | Where raised | User action |
|---|---|---|---|
| No base for bundle ID | `no_base_registered` | `resolveTarget` | Bake one, or `--local` |
| `--app` missing on `list`/`focused`/`clipboard` in VM mode | `missing_target` | `resolveTarget` | Pass `--vm <name>` or `--local` |
| Cannot resolve bundle ID from `--app` name | `app_not_found` | `resolveTarget` | App not installed/running on host; install or pass `--vm` |
| `--vm <name>` not in registry | `vm_not_found` | `resolveTarget` | `axon vm-list` to see options |
| VM has no IP yet | `vm_not_ready` | `resolveTarget` | Re-acquire or wait |
| SSH dispatch failed | `ssh_failed` | `sshDispatch` | stderr passed through; check VM is up, axon is on PATH inside VM |
| scp-back failed | `output_transfer_failed` | `applyScpBacks` | VM-side file present; manual recovery hint |

All errors are JSON to stderr matching the existing `printError` shape,
plus a `hint` field for typed router errors.

## Testing strategy

### Unit tests (no SSH, no VM)

`Tests/AxonUnitTests/RouterTests.swift`:
- `classifyCommand` returns the right class for every known command.
- `resolveTarget` matrix:
  - `--local` flag → `.local`.
  - `AXON_TARGET=local` env → `.local` unless `--local` explicitly off (n/a, just flag-on).
  - `--vm foo` with foo in registry → `.remote(entry)`.
  - `--vm foo` with foo missing → throws `vmNotFound`.
  - `--app Cicero` with bundle ID known and base registered, no running VM →
    requires injecting an "acquire" stub; `resolveTarget` calls a
    `VMAcquirer` protocol (production = real `vmAcquire`, test = stub
    returning a synthetic `VMEntry`).
  - `--app Cicero` with bundle ID known, base missing → throws
    `noBaseRegistered`.
  - `list` / `focused` / `clipboard` with no `--app`, no `--vm`, no `--local`
    → throws `missingTarget`.
- `remapFileOutputs`:
  - `screenshot --output /Users/me/x.png` → argv has temp path,
    `[ScpBack]` has the original.
  - `tree` (no file outputs) → unchanged argv, empty `[ScpBack]`.

### Integration tests (run the binary, no real VM)

`Tests/AxonIntegrationTests/RouterIntegrationTests.swift`:
- `AXON_TARGET=local axon click --app TextEdit --label Save` runs the
  existing local path (no router behavior change).
- `axon click --app Cicero` on a fixture environment with no `bases`
  registered → exit 2, JSON error `no_base_registered`.
- `axon vm-bake --for-bundle com.example.X --source ... --name x-base`
  writes a `bases` entry to a temp registry. Tests set `AXON_REGISTRY_PATH`
  env to point at a temp file; production code reads
  `AXON_REGISTRY_PATH ?? ~/.axon/vms.json`.

### E2E tests (real VM, opt-in)

Out of scope for this spec's CI gating. Guarded by an env check
(`AXON_E2E_VM=1`). One smoke test: bake a stock sequoia base with a
`--for-bundle com.apple.TextEdit`, acquire, run `axon screenshot --app
TextEdit --output /tmp/...png`, assert the PNG lands on the host.

### Existing E2E tests stay host-targeted

`Tests/AxonE2ETests/*` already drive host TextEdit/Finder. They get
`AXON_TARGET=local` set via the test runner so they keep working
unchanged after the routing flip.

## Out of scope

- Auto-provisioning the `axon` binary into VMs.
- A daemon protocol replacing per-call SSH.
- Running `vm-sync` automatically on `vm-acquire`.
- A `doctor --vm` mode that ssh-checks the VM. (Could come later — easy
  add once routing exists.)
- Multi-VM fan-out (running the same command across N parallel VMs).

## Migration

No breaking change to existing on-disk registries: the `bases` field is
optional and read with a default of `[]`. Users who never run
`vm-bake --for-bundle` and never set `AXON_TARGET=local` will see the new
hard-error the first time they run a UI command without a baked base —
the error message tells them exactly what to do.

E2E tests in this repo gain `AXON_TARGET=local` in their setUp; no
behavior change.
