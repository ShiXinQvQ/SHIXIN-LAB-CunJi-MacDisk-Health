import XCTest
@testable import ShixinDiskHealth

final class UpdateSafetyTests: XCTestCase, @unchecked Sendable {
    func testUpdateWaitsForEveryLeaseAndRejectsNewWork() async {
        await MainActor.run {
            let gate = UpdateActivityGate()
            let detection = gate.beginActivity()!
            let export = gate.beginActivity()!
            XCTAssertFalse(gate.beginUpdate())
            gate.endActivity(detection)
            gate.endActivity(detection)
            XCTAssertEqual(gate.activityCount, 1)
            XCTAssertFalse(gate.beginUpdate())
            gate.endActivity(export)
            XCTAssertTrue(gate.beginUpdate())
            XCTAssertNil(gate.beginActivity())
            gate.endUpdate()
            XCTAssertNotNil(gate.beginActivity())
        }
    }

    func testCancellationDoesNotReleaseTaskBeforeCleanup() async {
        let gate = await UpdateActivityGate()
        let task = Task { @MainActor in
            let lease = gate.beginActivity()!
            defer { gate.endActivity(lease) }
            while !Task.isCancelled { await Task.yield() }
            XCTAssertFalse(gate.beginUpdate())
            await Task.yield()
            XCTAssertFalse(gate.beginUpdate())
        }
        while await gate.activityCount == 0 { await Task.yield() }
        task.cancel()
        await task.value
        await MainActor.run { XCTAssertTrue(gate.beginUpdate()) }
    }

    func testTerminationWaitsAndPreventsNewTasks() async {
        let gate = await UpdateActivityGate()
        let lease = await gate.beginActivity()!
        await gate.beginTermination()
        await MainActor.run {
            XCTAssertNil(gate.beginActivity())
            XCTAssertFalse(gate.beginUpdate())
            XCTAssertEqual(gate.activityCount, 1)
        }
        let cleanup = Task { @MainActor in
            await Task.yield()
            gate.endActivity(lease)
        }
        await gate.waitUntilIdle()
        await cleanup.value
        await MainActor.run {
            XCTAssertEqual(gate.activityCount, 0)
            XCTAssertFalse(gate.beginUpdate())
            gate.cancelTermination()
            XCTAssertTrue(gate.beginUpdate())
        }
    }

    func testRepeatedQuitKeepsWaitingForCleanup() async {
        await MainActor.run {
            let gate = UpdateActivityGate.shared
            let lease = gate.beginActivity()!
            defer { gate.endActivity(lease); gate.cancelTermination() }
            let delegate = AppDelegate()
            delegate.terminationReply = { _ in }
            XCTAssertEqual(delegate.applicationShouldTerminate(.shared), .terminateLater)
            XCTAssertEqual(delegate.applicationShouldTerminate(.shared), .terminateLater)
        }
    }

    func testAppearanceExceptionOnlyRoutesMacOS27() {
        for major in [15, 26, 27, 28] {
            XCTAssertEqual(LabAppearanceProfile.usesStableSurfaces(majorVersion: major), major == 27)
        }
    }

    func testReleaseConfigurationRequiresKeyAndHTTPS() async {
        await MainActor.run {
            let valid: [String: Any] = [
                "CFBundleShortVersionString": "0.3.0", "CFBundleVersion": "7",
                "SUPublicEDKey": Data(repeating: 1, count: 32).base64EncodedString(),
                "SUFeedURL": "https://example.com/macdisk/appcast.xml"
            ]
            XCTAssertTrue(AppUpdateService.hasUpdateConfiguration(valid))
            for key in valid.keys {
                var missing = valid
                missing.removeValue(forKey: key)
                XCTAssertFalse(AppUpdateService.hasUpdateConfiguration(missing), key)
            }
            for feed in ["http://example.com/appcast.xml", "file:///tmp/appcast.xml", "not a URL"] {
                var invalid = valid
                invalid["SUFeedURL"] = feed
                XCTAssertFalse(AppUpdateService.hasUpdateConfiguration(invalid))
            }
        }
    }
}
