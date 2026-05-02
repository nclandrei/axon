import Foundation

// MARK: - Command Classification

public enum CommandClass: Equatable {
    case vmRoutable
    case alwaysLocal
}

// Must mirror every UI-driving case handled by main.swift's command switch.
// When you add a new UI command there, add its name here too — and a test in
// RouterClassifyTests.testVMRoutableCommands.
private let vmRoutableCommands: Set<String> = [
    "list", "launch", "tree", "click", "double-click", "right-click",
    "hover", "drag", "type", "key", "scroll", "screenshot", "activate",
    "close", "wait", "get-value", "focused", "window-info", "menu",
    "set-value", "move-resize", "clipboard", "wait-ready", "wait-for-value",
    "assert", "exists",
]

public func classifyCommand(_ command: String) -> CommandClass {
    vmRoutableCommands.contains(command) ? .vmRoutable : .alwaysLocal
}
