import XCTest
@testable import OpenUsage
@testable import OpenUsageCore

final class CommandLineInstallerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        // A space and an apostrophe in the path: the quoting must survive both.
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Install Tests's \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Runs the privileged command as the current user, which is enough inside the temp directory.
    private func installer(helperExists: Bool = true) throws -> CommandLineInstaller {
        let helper = root.appendingPathComponent("Fake.app/Contents/MacOS/openusage-cli")
        if helperExists {
            try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("#!/bin/sh\n".utf8).write(to: helper)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        }
        var installer = CommandLineInstaller(helper: helper)
        installer.linkPath = root.appendingPathComponent("bin/openusage").path
        installer.runPrivileged = { command in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return error.localizedDescription }
            process.waitUntilExit()
            return process.terminationStatus == 0 ? nil : "failed"
        }
        return installer
    }

    func testUnavailableWithoutTheHelper() throws {
        XCTAssertEqual(try installer(helperExists: false).status(), .unavailable)
    }

    func testInstallLinksTheHelperAndUninstallRemovesOnlyThatLink() async throws {
        let installer = try installer()
        XCTAssertEqual(installer.status(), .notInstalled)

        try await installer.install()
        XCTAssertEqual(installer.status(), .installed)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: installer.linkPath),
            installer.helper.path
        )

        try await installer.uninstall()
        XCTAssertEqual(installer.status(), .notInstalled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: installer.helper.path))
    }

    func testInstallReplacesALinkToAnotherCopy() async throws {
        let installer = try installer()
        try FileManager.default.createDirectory(atPath: (installer.linkPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: installer.linkPath, withDestinationPath: "/Applications/Other.app/Contents/MacOS/openusage-cli")
        XCTAssertEqual(installer.status(), .linkedElsewhere("/Applications/Other.app/Contents/MacOS/openusage-cli"))

        try await installer.install()
        XCTAssertEqual(installer.status(), .installed)
    }

    func testARealFileIsNeverReplacedOrRemoved() async throws {
        let installer = try installer()
        try FileManager.default.createDirectory(atPath: (installer.linkPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: URL(fileURLWithPath: installer.linkPath))
        XCTAssertEqual(installer.status(), .occupied)

        do { try await installer.install(); XCTFail("expected a refusal") } catch {
            XCTAssertEqual(error as? CommandLineInstaller.InstallError, .notOurs)
        }
        do { try await installer.uninstall(); XCTFail("expected a refusal") } catch {
            XCTAssertEqual(error as? CommandLineInstaller.InstallError, .notOurs)
        }
        XCTAssertEqual(try String(contentsOfFile: installer.linkPath, encoding: .utf8), "mine")
    }

    func testUninstallLeavesAnotherCopysLinkAlone() async throws {
        let installer = try installer()
        try FileManager.default.createDirectory(atPath: (installer.linkPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: installer.linkPath, withDestinationPath: "/elsewhere")
        do { try await installer.uninstall(); XCTFail("expected a refusal") } catch {
            XCTAssertEqual(error as? CommandLineInstaller.InstallError, .notOurs)
        }
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: installer.linkPath), "/elsewhere")
    }

    func testAFailedPrivilegedCommandSurfacesItsMessage() async throws {
        var installer = try installer()
        installer.runPrivileged = { _ in "Canceled." }
        do { try await installer.install(); XCTFail("expected a failure") } catch {
            XCTAssertEqual(error as? CommandLineInstaller.InstallError, .failed("Canceled."))
        }
    }

    func testQuotingKeepsHostileTextInsideOneWord() {
        XCTAssertEqual(CommandLineInstaller.shellQuoted("it's here"), #"'it'\''s here'"#)
        XCTAssertEqual(
            CommandLineInstaller.administratorScript(for: #"ln -s "a\b" c"#),
            #"do shell script "ln -s \"a\\b\" c" with administrator privileges"#
        )
    }
}
