import Cocoa
import CoreGraphics

// MARK: - Screenshot

/// Capture a screenshot of an app's window or the full screen
public func captureScreenshot(app: NSRunningApplication, outputPath: String, fullScreen: Bool, windowTitle: String?) -> ScreenshotOutput? {
    let pid = app.processIdentifier

    if fullScreen {
        return captureFullScreen(outputPath: outputPath)
    }

    // Find the app's window(s)
    guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        printError(code: "screenshot_failed", message: "Failed to get window list")
        return nil
    }

    // Find windows belonging to this app
    let appWindows = windowList.filter { info in
        guard let windowPID = info[kCGWindowOwnerPID as String] as? Int32 else { return false }
        if windowPID != pid { return false }

        // Filter by window title if specified
        if let title = windowTitle {
            guard let windowName = info[kCGWindowName as String] as? String else { return false }
            return windowName.localizedCaseInsensitiveContains(title)
        }

        // Skip tiny windows (menu bar items, etc.)
        if let bounds = info[kCGWindowBounds as String] as? [String: Any],
           let width = bounds["Width"] as? Double,
           let height = bounds["Height"] as? Double {
            return width > 50 && height > 50
        }
        return true
    }

    guard let window = appWindows.first,
          let windowID = window[kCGWindowNumber as String] as? CGWindowID else {
        printError(code: "window_not_found", message: "No visible window found for '\(app.localizedName ?? "unknown")'")
        return nil
    }

    // Capture the specific window at Retina resolution
    guard let image = CGWindowListCreateImage(
        .null,
        .optionIncludingWindow,
        windowID,
        [.bestResolution, .boundsIgnoreFraming]
    ) else {
        printError(code: "screenshot_failed", message: "CGWindowListCreateImage returned nil")
        return nil
    }

    return saveImage(image, to: outputPath)
}

/// Capture the full screen
public func captureFullScreen(outputPath: String) -> ScreenshotOutput? {
    guard let image = CGWindowListCreateImage(
        CGRect.infinite,
        .optionOnScreenOnly,
        kCGNullWindowID,
        [.bestResolution]
    ) else {
        printError(code: "screenshot_failed", message: "Full screen capture failed")
        return nil
    }
    return saveImage(image, to: outputPath)
}

/// Capture a screenshot of a specific element by cropping from the screen capture
public func captureElementScreenshot(app: NSRunningApplication, element: AXUIElement, outputPath: String) -> ScreenshotOutput? {
    // Get element position and size in screen coordinates
    guard let pos = axPointAttribute(element), let sz = axSizeAttribute(element) else {
        printError(code: "screenshot_failed", message: "Could not determine element position/size")
        return nil
    }

    // Element must have non-zero size
    guard sz.width > 0 && sz.height > 0 else {
        printError(code: "screenshot_failed", message: "Element has zero size")
        return nil
    }

    let elementRect = CGRect(x: pos.x, y: pos.y, width: sz.width, height: sz.height)

    // Capture the screen region containing the element
    guard let image = CGWindowListCreateImage(
        elementRect,
        .optionOnScreenOnly,
        kCGNullWindowID,
        [.bestResolution, .boundsIgnoreFraming]
    ) else {
        printError(code: "screenshot_failed", message: "Failed to capture element region")
        return nil
    }

    return saveImage(image, to: outputPath)
}

/// Save a CGImage as PNG to disk
private func saveImage(_ image: CGImage, to path: String) -> ScreenshotOutput? {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil) else {
        printError(code: "screenshot_failed", message: "Failed to create image destination at '\(path)'")
        return nil
    }

    CGImageDestinationAddImage(dest, image, nil)

    guard CGImageDestinationFinalize(dest) else {
        printError(code: "screenshot_failed", message: "Failed to write PNG to '\(path)'")
        return nil
    }

    return ScreenshotOutput(
        success: true,
        path: path,
        width: image.width,
        height: image.height
    )
}
