import XCTest
@testable import ShixinDiskHealthCore

final class SmartMergeRegressionTests: XCTestCase, @unchecked Sendable {
    private let healthyJSON = """
    {
      "json_format_version": [1, 0],
      "smartctl": {
        "version": [7, 5],
        "argv": ["smartctl", "-a", "--json", "/dev/disk0"],
        "exit_status": 0
      },
      "local_time": {
        "time_t": 1782427585
      },
      "device": {
        "name": "/dev/disk0",
        "info_name": "/dev/disk0",
        "type": "nvme",
        "protocol": "NVMe"
      },
      "model_name": "APPLE SSD TEST",
      "serial_number": "TESTSERIAL123",
      "firmware_version": "1.0",
      "nvme_version": {
        "string": "<1.2"
      },
      "nvme_number_of_namespaces": 3,
      "smart_status": {
        "passed": true
      },
      "nvme_smart_health_information_log": {
        "critical_warning": 0,
        "temperature": 45,
        "available_spare": 100,
        "available_spare_threshold": 99,
        "percentage_used": 2,
        "data_units_read": 1000,
        "data_units_written": 2000,
        "host_reads": 3000,
        "host_writes": 4000,
        "controller_busy_time": 5,
        "power_cycles": 6,
        "power_on_hours": 7,
        "unsafe_shutdowns": 8,
        "media_errors": 0,
        "num_err_log_entries": 0
      }
    }

    """

    private func combine(extendedStatus: Int32, extendedPassed: Bool = true) async throws -> SmartSnapshot {
        let coreData = Data(healthyJSON.utf8)
        let extendedData = Data(healthyJSON
            .replacingOccurrences(of: "\"exit_status\": 0", with: "\"exit_status\": \(extendedStatus)")
            .replacingOccurrences(of: "\"passed\": true", with: "\"passed\": \(extendedPassed)").utf8)
        let core = try SmartctlParser.parse(data: coreData, readMode: .bundled, smartctlPath: nil, processExitStatus: 0)
        let extended = try SmartctlParser.parse(data: extendedData, readMode: .bundled, smartctlPath: nil, processExitStatus: extendedStatus)
        let profile = SmartctlRunner.defaultDisk0Target().smartctlAccessProfile!
        return await SmartctlRunner().combine(
            coreSnapshot: core, coreRequest: .init(profile: profile, kind: .core),
            coreOutput: .init(stdout: coreData, stderr: Data(), exitStatus: 0),
            extendedSnapshot: extended, extendedRequest: .init(profile: profile, kind: .extended),
            extendedOutput: .init(stdout: extendedData, stderr: Data(), exitStatus: extendedStatus),
            location: .init(executableURL: URL(fileURLWithPath: "/fixture/smartctl"), mode: .bundled, label: "fixture"))
    }

    func testExtendedFailingHealthCannotBecomeHealthy() async throws {
        let result = try await combine(extendedStatus: 8, extendedPassed: false)
        XCTAssertEqual(result.smartctlExitStatus, 8)
        XCTAssertEqual(result.healthLevel, .risk)
    }

    func testExtendedThresholdFailureCannotBecomeHealthy() async throws {
        let result = try await combine(extendedStatus: 16)
        XCTAssertEqual(result.healthLevel, .risk)
    }

    func testSupplementalReadFailureIsNotDiskFailure() async throws {
        let result = try await combine(extendedStatus: 4)
        XCTAssertEqual(result.healthLevel, .healthy)
    }
}
