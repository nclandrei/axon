import XCTest
@testable import AxonLib

final class CLITests: XCTestCase {

    // MARK: - init(args:)

    func testInitWithEmptyArgs() {
        let cli = CLI(args: [])
        XCTAssertEqual(cli.args, [])
        XCTAssertNil(cli.command)
    }

    func testInitWithArgs() {
        let cli = CLI(args: ["tree", "--app", "Finder", "--depth", "3"])
        XCTAssertEqual(cli.args, ["tree", "--app", "Finder", "--depth", "3"])
        XCTAssertEqual(cli.command, "tree")
    }

    func testCommandReturnsFirstArg() {
        let cli = CLI(args: ["list"])
        XCTAssertEqual(cli.command, "list")
    }

    func testCommandNilWhenEmpty() {
        let cli = CLI(args: [])
        XCTAssertNil(cli.command)
    }

    // MARK: - flag()

    func testFlagReturnsTrueWhenPresent() {
        let cli = CLI(args: ["tree", "--compact"])
        XCTAssertTrue(cli.flag("compact"))
    }

    func testFlagReturnsFalseWhenAbsent() {
        let cli = CLI(args: ["tree", "--app", "Finder"])
        XCTAssertFalse(cli.flag("compact"))
    }

    func testFlagDoesNotMatchPartialNames() {
        let cli = CLI(args: ["--compacted"])
        XCTAssertFalse(cli.flag("compact"))
    }

    func testMultipleFlags() {
        let cli = CLI(args: ["tree", "--compact", "--verbose"])
        XCTAssertTrue(cli.flag("compact"))
        XCTAssertTrue(cli.flag("verbose"))
        XCTAssertFalse(cli.flag("debug"))
    }

    // MARK: - hasHelp()

    func testHasHelpWithDoubleDash() {
        let cli = CLI(args: ["--help"])
        XCTAssertTrue(cli.hasHelp())
    }

    func testHasHelpWithShortFlag() {
        let cli = CLI(args: ["-h"])
        XCTAssertTrue(cli.hasHelp())
    }

    func testHasHelpFalseWhenAbsent() {
        let cli = CLI(args: ["tree", "--app", "Finder"])
        XCTAssertFalse(cli.hasHelp())
    }

    func testHasHelpMixedWithOtherArgs() {
        let cli = CLI(args: ["tree", "--app", "Finder", "--help"])
        XCTAssertTrue(cli.hasHelp())
    }

    // MARK: - option()

    func testOptionReturnsValue() {
        let cli = CLI(args: ["tree", "--app", "Finder"])
        XCTAssertEqual(cli.option("app"), "Finder")
    }

    func testOptionReturnsNilWhenMissing() {
        let cli = CLI(args: ["tree", "--depth", "3"])
        XCTAssertNil(cli.option("app"))
    }

    func testOptionReturnsNilWhenNoValueFollows() {
        let cli = CLI(args: ["tree", "--app"])
        XCTAssertNil(cli.option("app"))
    }

    func testOptionMultipleOptions() {
        let cli = CLI(args: ["click", "--app", "Safari", "--id", "btn1"])
        XCTAssertEqual(cli.option("app"), "Safari")
        XCTAssertEqual(cli.option("id"), "btn1")
    }

    func testOptionValueWithSpaces() {
        let cli = CLI(args: ["tree", "--app", "Google Chrome"])
        XCTAssertEqual(cli.option("app"), "Google Chrome")
    }

    // MARK: - intOption()

    func testIntOptionParsesValidInt() {
        let cli = CLI(args: ["tree", "--depth", "5"])
        XCTAssertEqual(cli.intOption("depth", default: 3), 5)
    }

    func testIntOptionReturnsDefaultWhenMissing() {
        let cli = CLI(args: ["tree", "--app", "Finder"])
        XCTAssertEqual(cli.intOption("depth", default: 3), 3)
    }

    func testIntOptionReturnsDefaultOnInvalidValue() {
        let cli = CLI(args: ["tree", "--depth", "abc"])
        XCTAssertEqual(cli.intOption("depth", default: 3), 3)
    }

    func testIntOptionReturnsDefaultOnEmptyLikeValue() {
        let cli = CLI(args: ["tree", "--depth", "3.5"])
        XCTAssertEqual(cli.intOption("depth", default: 10), 10)
    }

    func testIntOptionZero() {
        let cli = CLI(args: ["tree", "--depth", "0"])
        XCTAssertEqual(cli.intOption("depth", default: 3), 0)
    }

    func testIntOptionNegative() {
        let cli = CLI(args: ["scroll", "--amount", "-5"])
        XCTAssertEqual(cli.intOption("amount", default: 3), -5)
    }
}
