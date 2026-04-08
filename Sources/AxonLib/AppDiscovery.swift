import Cocoa

// MARK: - App Discovery

/// Find a running app by name or bundle ID
public func findApp(name: String) -> NSRunningApplication? {
    let workspace = NSWorkspace.shared
    let apps = workspace.runningApplications.filter { $0.activationPolicy == .regular }

    // Try exact name match first
    if let app = apps.first(where: { $0.localizedName == name }) {
        return app
    }

    // Try bundle ID match
    if let app = apps.first(where: { $0.bundleIdentifier == name }) {
        return app
    }

    // Try case-insensitive name match
    if let app = apps.first(where: { $0.localizedName?.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
        return app
    }

    // Try case-insensitive contains match
    if let app = apps.first(where: { $0.localizedName?.localizedCaseInsensitiveContains(name) == true }) {
        return app
    }

    return nil
}

/// Get the AXUIElement for an app
public func appElement(for app: NSRunningApplication) -> AXUIElement {
    AXUIElementCreateApplication(app.processIdentifier)
}

/// List all running GUI apps
public func listApps() -> [AppInfo] {
    let workspace = NSWorkspace.shared
    return workspace.runningApplications
        .filter { $0.activationPolicy == .regular }
        .compactMap { app in
            guard let name = app.localizedName else { return nil }
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
        let available = listApps().map { $0.name }
        printError(
            code: "app_not_found",
            message: "No running app matching '\(name)'",
            available: available
        )
        exit(1)
    }
    return (app, appElement(for: app))
}

/// Resolve an element selector from CLI arguments, printing error and exiting if not found
public func resolveElement(appElement: AXUIElement, identifier: String?, label: String?, path: String?, appName: String) -> FoundElement {
    let selector: ElementSelector
    if let id = identifier {
        selector = .identifier(id)
    } else if let lbl = label {
        selector = .label(lbl)
    } else if let p = path {
        selector = .path(p)
    } else {
        printError(code: "missing_selector", message: "Provide --identifier, --label, or --path to select an element")
        exit(1)
    }

    guard let found = findElement(root: appElement, selector: selector) else {
        let available = collectAvailableIdentifiers(root: appElement)
        let selectorDesc: String
        switch selector {
        case .identifier(let v): selectorDesc = "identifier '\(v)'"
        case .label(let v): selectorDesc = "label '\(v)'"
        case .path(let v): selectorDesc = "path '\(v)'"
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
