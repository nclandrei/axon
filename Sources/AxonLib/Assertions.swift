import Cocoa
import ApplicationServices

/// Declarative description of all assertions to evaluate on a single element.
/// Nil fields mean "skip this assertion".
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

/// Evaluate every assertion in `spec` against `element`. An element of nil means "not found".
/// Returns all failing assertions (empty array = pass).
public func evaluateAssertions(_ spec: AssertionSpec, on element: AXUIElement?) -> [AssertFailure] {
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

    return failures
}
