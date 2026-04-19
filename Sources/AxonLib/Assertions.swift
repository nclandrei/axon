import Cocoa
import ApplicationServices

public struct AssertionSpec {
    public var exists: Bool = false
    public var notExists: Bool = false
    public var value: String? = nil
    public var valueMatches: String? = nil
    public var enabled: Bool = false
    public var disabled: Bool = false
    public var focused: Bool = false

    public init() {}
}

/// Snapshot of an element's state sampled once so assertions see a consistent view.
public struct ElementSnapshot {
    public let value: String?
    public let enabled: Bool?
    public let focused: Bool?

    public init(value: String?, enabled: Bool?, focused: Bool?) {
        self.value = value
        self.enabled = enabled
        self.focused = focused
    }

    public static func capture(from element: AXUIElement) -> ElementSnapshot {
        let value: String? = {
            var raw: AnyObject?
            let r = AXUIElementCopyAttributeValue(element, kAXValueAttribute as String as CFString, &raw)
            guard r == .success, let v = raw else { return nil }
            if let s = v as? String { return s }
            if let n = v as? NSNumber { return n.stringValue }
            return nil
        }()
        let enabled: Bool? = axBoolAttribute(element, kAXEnabledAttribute as String)
        let focused: Bool? = axBoolAttribute(element, kAXFocusedAttribute as String)
        return ElementSnapshot(value: value, enabled: enabled, focused: focused)
    }
}

public func evaluateAssertions(_ spec: AssertionSpec, on element: AXUIElement?) -> [AssertFailure] {
    let snapshot: ElementSnapshot? = element.map { ElementSnapshot.capture(from: $0) }
    return evaluateAssertions(spec, on: element, snapshot: snapshot)
}

/// Overload used by tests to inject a value without needing a real AXUIElement.
public func evaluateAssertions(_ spec: AssertionSpec, on element: AXUIElement?, resolvedValue: String?) -> [AssertFailure] {
    let snap = ElementSnapshot(value: resolvedValue, enabled: nil, focused: nil)
    return evaluateAssertions(spec, on: element, snapshot: snap)
}

public func evaluateAssertions(_ spec: AssertionSpec, on element: AXUIElement?, snapshot: ElementSnapshot?) -> [AssertFailure] {
    var failures: [AssertFailure] = []

    if spec.exists {
        if element == nil {
            failures.append(AssertFailure(assertion: "exists", expected: "true", actual: "false"))
        }
    }
    if spec.notExists {
        if element != nil {
            failures.append(AssertFailure(assertion: "not-exists", expected: "true", actual: "false"))
        }
    }

    if let expected = spec.value {
        let actual = snapshot?.value
        if actual != expected {
            failures.append(AssertFailure(assertion: "value", expected: expected, actual: actual ?? "<nil>"))
        }
    }
    if let pattern = spec.valueMatches {
        let actual = snapshot?.value
        guard let actual = actual else {
            failures.append(AssertFailure(assertion: "value-matches", expected: pattern, actual: "<nil>"))
            return failures
        }
        let matched = (try? NSRegularExpression(pattern: pattern))
            .flatMap { regex -> Bool? in
                let range = NSRange(actual.startIndex..., in: actual)
                return regex.firstMatch(in: actual, range: range) != nil
            } ?? false
        if !matched {
            failures.append(AssertFailure(assertion: "value-matches", expected: pattern, actual: actual))
        }
    }

    if spec.enabled {
        let actual = snapshot?.enabled
        if actual != true {
            failures.append(AssertFailure(assertion: "enabled", expected: "true", actual: actual.map(String.init) ?? "<nil>"))
        }
    }
    if spec.disabled {
        let actual = snapshot?.enabled
        if actual != false {
            failures.append(AssertFailure(assertion: "disabled", expected: "false", actual: actual.map(String.init) ?? "<nil>"))
        }
    }
    if spec.focused {
        let actual = snapshot?.focused
        if actual != true {
            failures.append(AssertFailure(assertion: "focused", expected: "true", actual: actual.map(String.init) ?? "<nil>"))
        }
    }

    return failures
}
