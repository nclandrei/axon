import Cocoa

// MARK: - App Discovery

/// Find a running app by name or bundle ID (searches both regular and accessory/menu-bar apps)
public func findApp(name: String) -> NSRunningApplication? {
    let workspace = NSWorkspace.shared
    // Search regular apps first, then accessory (menu bar) apps
    let regularApps = workspace.runningApplications.filter { $0.activationPolicy == .regular }
    let accessoryApps = workspace.runningApplications.filter { $0.activationPolicy == .accessory }
    let allApps = regularApps + accessoryApps

    // Try exact name match first
    if let app = allApps.first(where: { $0.localizedName == name }) {
        return app
    }

    // Try bundle ID match
    if let app = allApps.first(where: { $0.bundleIdentifier == name }) {
        return app
    }

    // Try case-insensitive name match
    if let app = allApps.first(where: { $0.localizedName?.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
        return app
    }

    // Try case-insensitive contains match
    if let app = allApps.first(where: { $0.localizedName?.localizedCaseInsensitiveContains(name) == true }) {
        return app
    }

    // Try matching by executable name for apps without localizedName (common for SPM-built menu bar apps)
    if let app = allApps.first(where: {
        guard let url = $0.executableURL else { return false }
        return url.lastPathComponent.localizedCaseInsensitiveCompare(name) == .orderedSame
    }) {
        return app
    }

    return nil
}

/// Get the AXUIElement for an app
public func appElement(for app: NSRunningApplication) -> AXUIElement {
    AXUIElementCreateApplication(app.processIdentifier)
}

/// List all running GUI apps (optionally including accessory/menu-bar apps)
public func listApps(includeAccessory: Bool = false) -> [AppInfo] {
    let workspace = NSWorkspace.shared
    return workspace.runningApplications
        .filter { app in
            if app.activationPolicy == .regular { return true }
            if includeAccessory && app.activationPolicy == .accessory { return true }
            return false
        }
        .compactMap { app in
            let name = app.localizedName ?? app.executableURL?.lastPathComponent
            guard let name = name else { return nil }
            return AppInfo(
                name: name,
                bundleID: app.bundleIdentifier,
                pid: app.processIdentifier
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}

/// Resolve app by name, printing error and exiting if not found
public func resolveApp(name: String) -> (NSRunningApplication, AXUIElement) {
    guard let app = findApp(name: name) else {
        let available = listApps(includeAccessory: true).map { $0.name }
        printError(
            code: "app_not_found",
            message: "No running app matching '\(name)'",
            available: available
        )
        exit(1)
    }
    return (app, appElement(for: app))
}

/// Resolve an element selector from CLI arguments, printing error and exiting if not found.
///
/// Priority: `--sheet`/`--alert` (combined with optional `--label` as a descendant filter),
/// then `--identifier`, then `--label`, then `--path`. At most one of sheet/alert should be true.
public func resolveElement(
    appElement: AXUIElement,
    identifier: String?,
    label: String?,
    path: String?,
    sheet: Bool = false,
    alert: Bool = false,
    appName: String
) -> FoundElement {
    let selector: ElementSelector
    if sheet {
        selector = .sheet(labelFilter: label)
    } else if alert {
        selector = .alert(labelFilter: label)
    } else if let id = identifier {
        selector = .identifier(id)
    } else if let lbl = label {
        selector = .label(lbl)
    } else if let p = path {
        selector = .path(p)
    } else {
        printError(code: "missing_selector", message: "Provide --identifier, --label, --path, --sheet, or --alert to select an element")
        exit(1)
    }

    guard let found = findElement(root: appElement, selector: selector) else {
        let available = collectAvailableIdentifiers(root: appElement)
        let selectorDesc: String
        switch selector {
        case .identifier(let v): selectorDesc = "identifier '\(v)'"
        case .label(let v): selectorDesc = "label '\(v)'"
        case .path(let v): selectorDesc = "path '\(v)'"
        case .sheet(let f): selectorDesc = f.map { "sheet with label '\($0)'" } ?? "frontmost sheet"
        case .alert(let f): selectorDesc = f.map { "alert with label '\($0)'" } ?? "frontmost alert"
        }
        printError(
            code: "element_not_found",
            message: "No element with \(selectorDesc) found in \(appName)",
            available: available
        )
        exit(1)
    }

    return found
}
