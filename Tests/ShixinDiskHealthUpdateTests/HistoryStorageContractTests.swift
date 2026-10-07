import XCTest
@testable import ShixinDiskHealthCore

/// Users' snapshots.json and speed-tests.json already contain these values.
/// Editing one would make that field unreadable in existing history; reword
/// the interface through `title` instead.
final class HistoryStorageContractTests: XCTestCase {
    func testStoredValuesNeverChange() throws {
        XCTAssertEqual(ReadCompleteness.allCases.map(\.rawValue), ["完整读取", "核心数据已读取，附加日志不可用", "核心字段缺失", "读取失败"])
        XCTAssertEqual(ReadMode.allCases.map(\.rawValue), [
            "App 内置 smartctl", "/opt/homebrew/bin/smartctl", "/usr/local/bin/smartctl",
            "PATH 中的 smartctl", "手动选择 smartctl", "Privileged Helper", "未知来源"
        ])
        XCTAssertEqual(DiskConnectionKind.allCases.map(\.rawValue), ["内置本地硬盘", "外置本地硬盘", "网络卷", "未知"])
        XCTAssertEqual(DiskProtocolFamily.allCases.map(\.rawValue), ["NVMe", "ATA / SATA", "SCSI / SAS", "SMART"])
        XCTAssertEqual(SpeedTestMode.allCases.map(\.rawValue), ["单次", "连续"])
        XCTAssertEqual(SpeedTestTargetKind.allCases.map(\.rawValue), ["默认临时目录", "用户选择目录"])
        XCTAssertEqual(try HealthLevel.allCases.map(encodedString), ["健康", "需要关注", "风险", "无法判断"])
    }

    func testHealthLevelStillReadsEveryStoredSpelling() throws {
        for (stored, level) in [("健康", HealthLevel.healthy), ("注意", .attention), ("需要关注", .attention),
                                ("风险", .risk), ("无法判断", .unknown), ("将来的写法", .unknown)] {
            XCTAssertEqual(try JSONDecoder().decode([HealthLevel].self, from: Data("[\"\(stored)\"]".utf8)), [level])
        }
    }

    func testUnknownStoredValuesKeepSnapshotHistoryReadable() throws {
        let directory = try temporaryDirectory()
        var snapshot = try SmartctlParser.parse(data: Data(Self.fixture.utf8), readMode: .bundled, smartctlPath: nil, processExitStatus: 0)
        snapshot.applyDiskTarget(SmartctlRunner.defaultDisk0Target())
        snapshot.readCompleteness = .complete
        let store = SnapshotStore(directory: directory)
        try store.save([snapshot])

        var json = try String(contentsOf: store.snapshotsURL, encoding: .utf8)
        for (stored, replacement) in [("\"完整读取\"", "\"某种将来的写法\""),
                                      ("\"App 内置 smartctl\"", "\"新的读取方式\""),
                                      ("\"内置本地硬盘\"", "\"新的连接类型\""),
                                      ("\"NVMe\"", "\"新的协议\"")] {
            XCTAssertTrue(json.contains(stored), "fixture should contain \(stored)")
            json = json.replacingOccurrences(of: stored, with: replacement)
        }
        try json.write(to: store.snapshotsURL, atomically: true, encoding: .utf8)

        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].readMode, .unknown)
        XCTAssertEqual(loaded[0].diskConnectionKind, .unknown)
        XCTAssertEqual(loaded[0].metrics.protocolFamily, .unknown)
        XCTAssertEqual(loaded[0].device.serialNumber, "TESTSERIAL123")
        XCTAssertEqual(loaded[0].metrics.powerOnHours, 7)
    }

    func testUnknownStoredValuesKeepSpeedTestHistoryReadable() throws {
        let directory = try temporaryDirectory()
        let store = SpeedTestStore(directory: directory, cacheDirectory: directory.appendingPathComponent("cache"))
        let result = SpeedTestResult(
            startedAt: Date(timeIntervalSince1970: 1_790_000_000), completedAt: Date(timeIntervalSince1970: 1_790_000_060),
            mode: .continuous, cycleIndex: 2, testSizeBytes: 1_000_000_000,
            writeAverageMBps: 5_000, writePeakMBps: 6_000, readAverageMBps: 6_500, readPeakMBps: 7_000,
            writeDurationSeconds: 0.2, readDurationSeconds: 0.15,
            targetKind: .defaultCacheDirectory, targetDisplayName: "默认临时目录",
            targetConnectionKind: .internalPhysical, volumeName: "Macintosh HD",
            volumeAvailableBeforeBytes: 10, volumeAvailableAfterBytes: 10,
            appVersion: "0.3.0", runnerVersion: "test"
        )
        try store.save([result])

        var json = try String(contentsOf: store.resultsURL, encoding: .utf8)
        for (stored, replacement) in [("\"连续\"", "\"新的模式\""),
                                      ("\"默认临时目录\"", "\"新的目标\""),
                                      ("\"内置本地硬盘\"", "\"新的连接类型\"")] {
            XCTAssertTrue(json.contains(stored), "fixture should contain \(stored)")
            json = json.replacingOccurrences(of: stored, with: replacement)
        }
        try json.write(to: store.resultsURL, atomically: true, encoding: .utf8)

        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].mode, .single)
        XCTAssertEqual(loaded[0].targetKind, .userSelectedDirectory)
        XCTAssertEqual(loaded[0].targetConnectionKind, .unknown)
        XCTAssertEqual(loaded[0].writeAverageMBps, 5_000)
    }

    private func encodedString(_ level: HealthLevel) throws -> String {
        try JSONDecoder().decode([String].self, from: JSONEncoder().encode([level]))[0]
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CunJiHistoryContract-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private static let fixture = """
    {
      "json_format_version": [1, 0],
      "smartctl": { "version": [7, 5], "argv": ["smartctl", "-a", "--json", "/dev/disk0"], "exit_status": 0 },
      "device": { "name": "/dev/disk0", "info_name": "/dev/disk0", "type": "nvme", "protocol": "NVMe" },
      "model_name": "APPLE SSD TEST",
      "serial_number": "TESTSERIAL123",
      "firmware_version": "1.0",
      "smart_status": { "passed": true },
      "nvme_smart_health_information_log": {
        "critical_warning": 0, "temperature": 45, "available_spare": 100, "available_spare_threshold": 99,
        "percentage_used": 2, "data_units_read": 1000, "data_units_written": 2000, "host_reads": 3000,
        "host_writes": 4000, "controller_busy_time": 5, "power_cycles": 6, "power_on_hours": 7,
        "unsafe_shutdowns": 8, "media_errors": 0, "num_err_log_entries": 0
      }
    }
    """
}
