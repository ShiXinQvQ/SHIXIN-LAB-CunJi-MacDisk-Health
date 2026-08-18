import Darwin
import Foundation
import ShixinDiskHealthCore

enum SelfTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): message
        }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw SelfTestFailure.failed(message)
    }
}

func expectThrows(_ message: String, _ block: () throws -> Void) throws {
    do {
        try block()
        throw SelfTestFailure.failed(message)
    } catch is SelfTestFailure {
        throw SelfTestFailure.failed(message)
    } catch {
        return
    }
}

@main
struct ShixinDiskHealthSelfTest {
    static func main() async {
        if CommandLine.arguments.contains("--process-fixture") {
            let stdoutChunk = Data(repeating: 0x41, count: 64 * 1_024)
            let stderrChunk = Data(repeating: 0x42, count: 64 * 1_024)
            for _ in 0..<32 {
                try? FileHandle.standardOutput.write(contentsOf: stdoutChunk)
                try? FileHandle.standardError.write(contentsOf: stderrChunk)
            }
            return
        }
        if CommandLine.arguments.contains("--process-unbounded-fixture") {
            let stdoutChunk = Data(repeating: 0x41, count: 64 * 1_024)
            let stderrChunk = Data(repeating: 0x42, count: 64 * 1_024)
            while true {
                do {
                    try FileHandle.standardOutput.write(contentsOf: stdoutChunk)
                    try FileHandle.standardError.write(contentsOf: stderrChunk)
                } catch {
                    return
                }
            }
        }
        do {
            try runRuntimeNamespaceSafetyTest()
            try runHealthyExitZeroTest()
            try runATAProtocolTest()
            try runSCSIProtocolTest()
            try runExitFourSupplementalLogTest()
            try runHealthFailureExitBitsTest()
            try runMergedExitStatusTest()
            try runUnknownProtocolSafetyTest()
            try runCriticalWarningTest()
            try runMediaErrorsTest()
            try runSpareBelowThresholdTest()
            try runMissingCoreFieldsTest()
            try runMissingDeviceIdentityTest()
            try runNonJSONTest()
            try await runPolicyTest()
            try runDiskIdentityTest()
            try runDiskInventoryBasicTest()
            try await runHardwareProfileBasicTest()
            try runOldSnapshotReevaluationTest()
            try runLegacySnapshotDecodeTest()
            try runSerialAndExportTest()
            try await runProcessExecutorTest()
            try runSpeedTestSizeOptionTest()
            try runSpeedTestPathPolicyTest()
            try runSpeedTestStoreTest()
            try runPreviousVersionHistoryImportTest()
            try await runSpeedTestRunnerSmallFileTest()
            try await runSpeedTestCancellationCleanupTest()
            try runSpeedTestCrashLedgerCleanupTest()
            if CommandLine.arguments.contains("--live") {
                _ = try await runLiveProbe(saveToHistory: false)
            }
            if CommandLine.arguments.contains("--live-all") {
                try await runLiveInventoryProbe()
            }
            if CommandLine.arguments.contains("--save-live-snapshot") {
                _ = try await runLiveProbe(saveToHistory: true)
            }
            print("ShixinDiskHealthSelfTest passed")
        } catch {
            fputs("ShixinDiskHealthSelfTest failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func runRuntimeNamespaceSafetyTest() throws {
        if Bundle.main.object(forInfoDictionaryKey: "SHIXINAppSupportDirectoryName") == nil {
            try expect(
                AppRuntimeConfiguration.appSupportDirectoryName == "SHIXIN LAB MacDisk Health v2",
                "unpackaged source execution must fall back to the isolated v2 namespace"
            )
            try expect(
                AppRuntimeConfiguration.speedTestCacheDirectoryName == "SHIXIN LAB MacDisk Health v2",
                "unpackaged source execution must use the isolated v2 speed-test cache namespace"
            )
            try expect(
                AppRuntimeConfiguration.previousVersionAppSupportDirectoryName == "SHIXIN LAB MacDisk Health",
                "unpackaged v2 execution must import only from the published namespace"
            )
        }
        try expect(
            AppRuntimeConfiguration.previousVersionAppSupportDirectoryName(
                for: AppRuntimeConfiguration.publishedAppSupportDirectoryName
            ) == AppRuntimeConfiguration.internalV2AppSupportDirectoryName,
            "published 0.2.0 must import only from the internal-v2 namespace"
        )
        try expect(
            AppRuntimeConfiguration.previousVersionAppSupportDirectoryName(for: "unexpected namespace") == nil,
            "unknown data namespaces must not gain an implicit migration source"
        )
    }

    private static func runHealthyExitZeroTest() throws {
        let data = Data(healthyExitZeroJSON.utf8)
        let snapshot = try SmartctlParser.parse(
            data: data,
            readMode: .homebrewAppleSilicon,
            smartctlPath: "/opt/homebrew/bin/smartctl",
            processExitStatus: 0
        )

        try expect(snapshot.device.modelName == "APPLE SSD TEST", "model_name parse failed")
        try expect(snapshot.device.serialNumber == "TESTSERIAL123", "serial_number parse failed")
        try expect(snapshot.metrics.temperatureCelsius == 45, "temperature parse failed")
        try expect(snapshot.metrics.percentageUsed == 2, "percentage_used parse failed")
        try expect(snapshot.metrics.dataUnitsRead == 1_000, "data_units_read parse failed")
        try expect(snapshot.metrics.dataUnitsWritten == 2_000, "data_units_written parse failed")
        try expect(snapshot.smartctlExitStatus == 0, "exit status parse failed")
        try expect(snapshot.healthLevel == .healthy, "normal SMART data should be healthy")
        try expect(snapshot.displayReadCompleteness == .complete, "exit 0 should be complete")
    }

    private static func runExitFourSupplementalLogTest() throws {
        let snapshot = try SmartctlParser.parse(
            data: Data(exitFourSupplementalLogJSON.utf8),
            readMode: .homebrewAppleSilicon,
            smartctlPath: "/opt/homebrew/bin/smartctl",
            processExitStatus: 4
        )
        try expect(snapshot.healthLevel == .healthy, "supplemental log exit 4 must not change disk health")
        try expect(snapshot.displayReadCompleteness == .coreCompleteSupplementalUnavailable, "exit 4 supplemental log should be limited read")
        try expect(snapshot.healthReasons.joined().contains("Critical Warning 为 0"), "healthy explanation should mention core health")
    }

    private static func runATAProtocolTest() throws {
        let snapshot = try parse(healthyATAJSON)
        try expect(snapshot.metrics.effectiveProtocolFamily == .ata, "ATA protocol family parse failed")
        try expect(snapshot.device.modelName == "SATA SSD TEST", "ATA model parse failed")
        try expect(snapshot.ataAttributes?.count == 9, "ATA attribute table parse failed")
        try expect(snapshot.metrics.reallocatedSectorCount == 0, "ATA reallocated sectors parse failed")
        try expect(snapshot.metrics.currentPendingSectorCount == 0, "ATA pending sectors parse failed")
        try expect(snapshot.metrics.offlineUncorrectableSectorCount == 0, "ATA offline uncorrectable parse failed")
        try expect(snapshot.metrics.crcErrorCount == 0, "ATA CRC parse failed")
        try expect(snapshot.metrics.temperatureCelsius == 37, "ATA temperature parse failed")
        try expect(snapshot.metrics.percentageUsed == 8, "ATA lifetime normalization failed")
        try expect(snapshot.healthLevel == .healthy, "healthy ATA fixture should be healthy")
        try expect(snapshot.displayReadCompleteness == .complete, "healthy ATA fixture should be complete")

        let pendingJSON = healthyATAJSON.replacingOccurrences(
            of: #"{"id":197,"name":"Current_Pending_Sector","value":100,"worst":100,"thresh":0,"when_failed":"","raw":{"value":0,"string":"0"}}"#,
            with: #"{"id":197,"name":"Current_Pending_Sector","value":100,"worst":100,"thresh":0,"when_failed":"","raw":{"value":2,"string":"2"}}"#
        )
        let pending = try parse(pendingJSON)
        try expect(pending.healthLevel == .risk, "ATA pending sectors must be risk")

        let thresholdJSON = healthyATAJSON.replacingOccurrences(
            of: #"{"id":5,"name":"Reallocated_Sector_Ct","value":100,"worst":100,"thresh":10,"when_failed":"","raw":{"value":0,"string":"0"}}"#,
            with: #"{"id":5,"name":"Reallocated_Sector_Ct","value":5,"worst":5,"thresh":10,"when_failed":"now","raw":{"value":12,"string":"12"}}"#
        )
        let threshold = try parse(thresholdJSON)
        try expect(threshold.metrics.ataFailingAttributeCount == 1, "ATA failing threshold count parse failed")
        try expect(threshold.healthLevel == .risk, "ATA threshold failure must be risk")
        try expect(
            ATASmartAttribute(id: 5, name: "Reallocated_Sector_Ct", whenFailed: "now").isFailingNow,
            "official smartmontools when_failed=now must be recognized without normalized values"
        )

        let pastFailureJSON = healthyATAJSON.replacingOccurrences(
            of: #"{"id":5,"name":"Reallocated_Sector_Ct","value":100,"worst":100,"thresh":10,"when_failed":"","raw":{"value":0,"string":"0"}}"#,
            with: #"{"id":5,"name":"Reallocated_Sector_Ct","value":100,"worst":9,"thresh":10,"when_failed":"In_the_past","raw":{"value":0,"string":"0"}}"#
        )
        let pastFailure = try parse(pastFailureJSON)
        try expect(pastFailure.metrics.ataFailingAttributeCount == 0, "past ATA threshold failure must not be treated as failing now")
        try expect(pastFailure.metrics.ataPastFailureAttributeCount == 1, "past ATA threshold failure count parse failed")
        try expect(pastFailure.healthLevel == .attention, "past ATA threshold failure should require attention, not report current risk")

        let mediaWearoutJSON = healthyATAJSON.replacingOccurrences(
            of: #"{"id":202,"name":"Percent_Lifetime_Remain","value":92,"worst":92,"thresh":1,"when_failed":"","raw":{"value":92,"string":"92"}}"#,
            with: #"{"id":233,"name":"Media_Wearout_Indicator","value":92,"worst":92,"thresh":1,"when_failed":"","raw":{"value":0,"string":"0"}}"#
        )
        let mediaWearout = try parse(mediaWearoutJSON)
        try expect(mediaWearout.metrics.percentageUsed == 8, "ATA remaining-life normalization must prefer normalized current value over vendor raw value")
    }

    private static func runSCSIProtocolTest() throws {
        let snapshot = try parse(healthySCSIJSON)
        try expect(snapshot.metrics.effectiveProtocolFamily == .scsi, "SCSI protocol family parse failed")
        try expect(snapshot.scsiErrorCounters?.hasData == true, "SCSI counter table parse failed")
        try expect(snapshot.metrics.scsiReadUncorrectedErrors == 0, "SCSI read errors parse failed")
        try expect(snapshot.metrics.scsiWriteUncorrectedErrors == 0, "SCSI write errors parse failed")
        try expect(snapshot.metrics.scsiGrownDefectList == 0, "SCSI grown defects parse failed")
        try expect(snapshot.metrics.scsiNonMediumErrorCount == 0, "nested SCSI non-medium error count parse failed")
        try expect(snapshot.healthLevel == .healthy, "healthy SCSI fixture should be healthy")

        let riskyJSON = healthySCSIJSON.replacingOccurrences(
            of: #""total_uncorrected_errors": 0"#,
            with: #""total_uncorrected_errors": 3"#,
            maxReplacements: 1
        )
        let risky = try parse(riskyJSON)
        try expect(risky.healthLevel == .risk, "SCSI uncorrected read errors must be risk")
    }

    private static func runHealthFailureExitBitsTest() throws {
        let json = healthyExitZeroJSON.replacingOccurrences(of: #""exit_status": 0"#, with: #""exit_status": 8"#)
        let snapshot = try parse(json)
        try expect(snapshot.metrics.smartPassed == false, "smartctl health-failure exit bit must override a conflicting passed flag")
        try expect(snapshot.healthLevel == .risk, "smartctl health-failure exit bit must produce a risk result")
        try expect(snapshot.displayReadCompleteness == .complete, "health-failure bits alone must not imply an incomplete read")

        let historyJSON = healthyExitZeroJSON.replacingOccurrences(
            of: #""exit_status": 0"#,
            with: #""exit_status": 192"#
        )
        let historySnapshot = try parse(historyJSON)
        try expect(historySnapshot.metrics.smartPassed == true, "history-only exit bits must not override a passing current health status")
        try expect(historySnapshot.healthLevel == .attention, "error and self-test history bits must produce an attention result")
        try expect(historySnapshot.displayReadCompleteness == .complete, "history-only exit bits must preserve complete read status")

        let pastThresholdJSON = healthyExitZeroJSON.replacingOccurrences(
            of: #""exit_status": 0"#,
            with: #""exit_status": 32"#
        )
        let pastThresholdSnapshot = try parse(pastThresholdJSON)
        try expect(pastThresholdSnapshot.healthLevel == .attention, "past ATA threshold exit bit must produce an attention result")
        try expect(pastThresholdSnapshot.displayReadCompleteness == .complete, "past ATA threshold exit bit must preserve complete read status")
    }

    private static func runMergedExitStatusTest() throws {
        try expect(
            SmartctlRunner.mergeExitStatuses(8, 0) == 8,
            "an extended success must not erase a core health-failure exit bit"
        )
        try expect(
            SmartctlRunner.mergeExitStatuses(0, 64, 128) == 192,
            "core and extended history bits must be preserved together"
        )
        try expect(
            SmartctlRunner.mergeExitStatuses(nil, -1, 32) == 32,
            "missing and synthetic failure statuses must not erase a valid status"
        )
        try expect(
            SmartctlRunner.mergeExitStatuses(nil, -1) == nil,
            "no valid smartctl exit status should remain unknown"
        )
    }

    private static func runUnknownProtocolSafetyTest() throws {
        let json = #"""
        {
          "smartctl": {"version": [7, 5], "exit_status": 0},
          "device": {"name": "/dev/disk9", "type": "mystery", "protocol": "Mystery"},
          "model_name": "GENERIC BRIDGE",
          "smart_status": {"passed": true},
          "temperature": {"current": 30}
        }
        """#
        let snapshot = try parse(json)
        try expect(snapshot.metrics.effectiveProtocolFamily == .unknown, "unknown protocol must remain unknown")
        try expect(snapshot.healthLevel == .unknown, "limited generic fields must not be promoted to a healthy conclusion")
        try expect(snapshot.displayReadCompleteness == .coreMissing, "unknown protocol should report incomplete core coverage")
    }

    private static func runCriticalWarningTest() throws {
        let snapshot = try parse(modifiedJSON(healthyExitZeroJSON, replacements: ["\"critical_warning\": 0": "\"critical_warning\": 1"]))
        try expect(snapshot.healthLevel == .risk, "critical warning must be risk")
    }

    private static func runMediaErrorsTest() throws {
        let snapshot = try parse(modifiedJSON(healthyExitZeroJSON, replacements: ["\"media_errors\": 0": "\"media_errors\": 2"]))
        try expect(snapshot.healthLevel == .risk, "media errors must be risk")
    }

    private static func runSpareBelowThresholdTest() throws {
        let json = modifiedJSON(healthyExitZeroJSON, replacements: [
            "\"available_spare\": 100": "\"available_spare\": 98",
            "\"available_spare_threshold\": 99": "\"available_spare_threshold\": 99"
        ])
        let snapshot = try parse(json)
        try expect(snapshot.healthLevel == .risk, "available spare below threshold must be risk")
    }

    private static func runMissingCoreFieldsTest() throws {
        let json = """
        {
          "smartctl": {"version": [7,5], "exit_status": 0},
          "device": {"name": "/dev/disk0", "type": "nvme", "protocol": "NVMe"},
          "model_name": "APPLE SSD PARTIAL"
        }
        """
        try expectThrows("missing core fields should throw") {
            _ = try SmartctlParser.parse(
                data: Data(json.utf8),
                readMode: .unknown,
                smartctlPath: nil,
                processExitStatus: 0
            )
        }
    }

    private static func runMissingDeviceIdentityTest() throws {
        guard var object = try JSONSerialization.jsonObject(with: Data(healthyExitZeroJSON.utf8)) as? [String: Any] else {
            throw SelfTestFailure.failed("healthy fixture should be a JSON object")
        }
        object.removeValue(forKey: "device")
        let data = try JSONSerialization.data(withJSONObject: object)
        var snapshot = try SmartctlParser.parse(
            data: data,
            readMode: .unknown,
            smartctlPath: nil,
            processExitStatus: 0
        )
        try expect(snapshot.device.deviceName == "未返回", "missing device name must not fall back to /dev/disk0")

        let target = DiskTarget(
            id: "device:/dev/disk4",
            displayName: "External Test SSD",
            connectionKind: .externalPhysical,
            smartSupportStatus: .supported,
            smartctlAccessProfile: SmartctlAccessProfile(devicePath: "/dev/disk4"),
            identityKey: DiskIdentityKey(rawValue: "device:/dev/disk4", source: "self-test")
        )
        try SmartctlRunner.validateReportedDevicePath(snapshot.device.deviceName, expectedDevicePath: "/dev/disk4")
        snapshot.applyDiskTarget(target)
        try expect(snapshot.device.deviceName == "/dev/disk4", "enumerated target should fill a missing device name")

        try expectThrows("mismatched smartctl device output should be rejected") {
            try SmartctlRunner.validateReportedDevicePath("/dev/disk0", expectedDevicePath: "/dev/disk4")
        }
    }

    private static func runNonJSONTest() throws {
        try expectThrows("non JSON should throw") {
            _ = try SmartctlParser.parse(
                data: Data("not json".utf8),
                readMode: .unknown,
                smartctlPath: nil,
                processExitStatus: 1
            )
        }
    }

    private static func runPolicyTest() async throws {
        let externalProfile = SmartctlAccessProfile(devicePath: "/dev/disk4", allowedDeviceTypes: [.sntRealtek, .auto, .sat, .scsi])
        try SmartctlRunner.validate(
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/smartctl"),
            request: SmartctlCommandRequest(profile: externalProfile, deviceType: .sntRealtek, kind: .core)
        )
        try SmartctlRunner.validate(
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/smartctl"),
            request: SmartctlCommandRequest(profile: externalProfile, deviceType: .sat, kind: .core)
        )
        try SmartctlRunner.validate(
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/smartctl"),
            request: SmartctlCommandRequest(profile: externalProfile, deviceType: .sat, kind: .extended)
        )

        try SmartctlRunner.validate(
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/smartctl"),
            arguments: ["-i", "-H", "-A", "--json", "/dev/disk0"]
        )
        try SmartctlRunner.validate(
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/smartctl"),
            arguments: ["-a", "--json", "/dev/disk0"]
        )

        try expectThrows("shell execution should be rejected") {
            try SmartctlRunner.validate(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "smartctl -a --json /dev/disk0"]
            )
        }

        try expectThrows("non-whitelisted arguments should be rejected") {
            try SmartctlRunner.validate(
                executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/smartctl"),
                arguments: ["--scan"]
            )
        }

        try expectThrows("partition device path should be rejected") {
            let profile = SmartctlAccessProfile(devicePath: "/dev/disk0s1", allowedDeviceTypes: [.auto])
            try SmartctlRunner.validate(
                executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/smartctl"),
                request: SmartctlCommandRequest(profile: profile, kind: .core)
            )
        }

        try expectThrows("rdisk device path should be rejected") {
            let profile = SmartctlAccessProfile(devicePath: "/dev/rdisk0", allowedDeviceTypes: [.auto])
            try SmartctlRunner.validate(
                executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/smartctl"),
                request: SmartctlCommandRequest(profile: profile, kind: .core)
            )
        }

        try expectThrows("non-enumerated device type should be rejected") {
            let profile = SmartctlAccessProfile(devicePath: "/dev/disk0", allowedDeviceTypes: [.auto])
            try SmartctlRunner.validate(
                executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/smartctl"),
                request: SmartctlCommandRequest(profile: profile, deviceType: .sat, kind: .core)
            )
        }

        try expectThrows("non-enumerated SNT bridge type should be rejected") {
            let profile = SmartctlAccessProfile(devicePath: "/dev/disk4", allowedDeviceTypes: [.auto])
            try SmartctlRunner.validate(
                executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/smartctl"),
                request: SmartctlCommandRequest(profile: profile, deviceType: .sntRealtek, kind: .core)
            )
        }

        let enumeratedIdentity = DiskIdentityKey(
            rawValue: "media:11111111-2222-3333-4444-555555555555",
            source: "disk-arbitration-media-uuid"
        )
        let enumeratedTarget = DiskTarget(
            id: "runtime-disk:/dev/disk4",
            displayName: "Enumerated Disk",
            connectionKind: .externalPhysical,
            smartSupportStatus: .supported,
            smartctlAccessProfile: SmartctlAccessProfile(devicePath: "/dev/disk4", allowedDeviceTypes: [.auto]),
            identityKey: enumeratedIdentity
        )
        let enumeratedInventory = DiskInventory(targets: [enumeratedTarget])
        var forgedTypesTarget = enumeratedTarget
        forgedTypesTarget.smartctlAccessProfile = SmartctlAccessProfile(
            devicePath: "/dev/disk4",
            allowedDeviceTypes: [.auto, .sntRealtek]
        )
        let resolvedTarget = SmartctlRunner.resolveEnumeratedTarget(forgedTypesTarget, in: enumeratedInventory)
        try expect(
            resolvedTarget?.smartctlAccessProfile?.allowedDeviceTypes == [.auto],
            "runner preflight must replace caller-provided device types with the fresh enumerated profile"
        )

        let forgedPathTarget = DiskTarget(
            id: "runtime-disk:/dev/disk99",
            displayName: "Forged Disk",
            connectionKind: .externalPhysical,
            smartSupportStatus: .supported,
            smartctlAccessProfile: SmartctlAccessProfile(devicePath: "/dev/disk99", allowedDeviceTypes: [.auto])
        )
        try expect(
            SmartctlRunner.resolveEnumeratedTarget(forgedPathTarget, in: enumeratedInventory) == nil,
            "runner preflight must reject a whole-disk-shaped path that was not enumerated"
        )

        let rejectingRunner = SmartctlRunner(inventoryProvider: { DiskInventory() })
        let rejectedOutcome = await rejectingRunner.read(target: enumeratedTarget)
        guard case .failure(let rejectedFailure) = rejectedOutcome else {
            throw SelfTestFailure.failed("runner must reject a target missing from its live inventory")
        }
        try expect(
            rejectedFailure.title == "所选硬盘未通过实时枚举校验",
            "runner must fail before locating or executing smartctl for a non-enumerated target"
        )
    }

    private static func runDiskIdentityTest() throws {
        var snapshot = try parse(healthyExitZeroJSON)
        let identity = DiskIdentityKey(rawValue: "media:test-disk", source: "self-test")
        let target = DiskTarget(
            id: identity.rawValue,
            displayName: "External Test SSD",
            connectionKind: .externalPhysical,
            smartSupportStatus: .supported,
            smartctlAccessProfile: SmartctlAccessProfile(devicePath: "/dev/disk4", allowedDeviceTypes: [.auto, .sat]),
            identityKey: identity,
            isLocalVolume: true,
            isInternal: false,
            protocolName: "USB"
        )
        snapshot.applyDiskTarget(target)
        try expect(snapshot.diskConnectionKind == .externalPhysical, "snapshot should retain disk connection kind")
        try expect(snapshot.diskDevicePath == "/dev/disk4", "snapshot should retain selected disk path")
        try expect(snapshot.device.deviceName == "/dev/disk4", "snapshot device name should match selected target")
        try expect(snapshot.effectiveDiskIdentity.rawValue == "serial:TESTSERIAL123", "snapshot identity should prefer smartctl serial")
        try expect(snapshot.belongs(to: target), "snapshot should match its target identity")

        let collidingWeakIdentity = DiskIdentityKey(
            rawValue: "model-size-protocol:SAME:1000:USB",
            source: "model-size-protocol"
        )
        let first = DiskTarget(
            id: "runtime-disk:/dev/disk4",
            displayName: "Same Disk A",
            connectionKind: .externalPhysical,
            smartSupportStatus: .supported,
            smartctlAccessProfile: SmartctlAccessProfile(devicePath: "/dev/disk4"),
            identityKey: collidingWeakIdentity
        )
        let second = DiskTarget(
            id: "runtime-disk:/dev/disk5",
            displayName: "Same Disk B",
            connectionKind: .externalPhysical,
            smartSupportStatus: .supported,
            smartctlAccessProfile: SmartctlAccessProfile(devicePath: "/dev/disk5"),
            identityKey: collidingWeakIdentity
        )
        var collisionSnapshot = try parse(healthyExitZeroJSON)
        collisionSnapshot.applyDiskTarget(first)
        try expect(first.id != second.id, "runtime target IDs must differ by device node")
        try expect(!collisionSnapshot.belongs(to: second), "weak identity collision must not match another live device node")

        let strongIdentity = DiskIdentityKey(rawValue: "media:stable-test", source: "disk-arbitration-media-uuid")
        var strongSnapshot = try parse(healthyExitZeroJSON)
        strongSnapshot.applyDiskTarget(DiskTarget(
            id: "runtime-disk:/dev/disk4",
            displayName: "Stable Disk",
            connectionKind: .externalPhysical,
            smartSupportStatus: .supported,
            smartctlAccessProfile: SmartctlAccessProfile(devicePath: "/dev/disk4"),
            identityKey: strongIdentity
        ))
        let reconnected = DiskTarget(
            id: "runtime-disk:/dev/disk7",
            displayName: "Stable Disk",
            connectionKind: .externalPhysical,
            smartSupportStatus: .supported,
            smartctlAccessProfile: SmartctlAccessProfile(devicePath: "/dev/disk7"),
            identityKey: strongIdentity
        )
        try expect(strongSnapshot.belongs(to: reconnected), "strong media identity should survive a device-node change")

        let conflictingStrongTarget = DiskTarget(
            id: "runtime-disk:/dev/disk4",
            displayName: "Different Disk",
            connectionKind: .externalPhysical,
            smartSupportStatus: .supported,
            smartctlAccessProfile: SmartctlAccessProfile(devicePath: "/dev/disk4"),
            identityKey: DiskIdentityKey(rawValue: "media:different-test", source: "disk-arbitration-media-uuid")
        )
        try expect(
            !strongSnapshot.belongs(to: conflictingStrongTarget),
            "conflicting strong identities must win over a reused device node"
        )

        let reconnectedInventory = DiskInventory(targets: [reconnected, conflictingStrongTarget])
        let originalStrongTarget = DiskTarget(
            id: "runtime-disk:/dev/disk4",
            displayName: "Stable Disk",
            connectionKind: .externalPhysical,
            smartSupportStatus: .supported,
            smartctlAccessProfile: SmartctlAccessProfile(devicePath: "/dev/disk4"),
            identityKey: strongIdentity
        )
        try expect(
            reconnectedInventory.smartTarget(matching: originalStrongTarget)?.id == reconnected.id,
            "fresh inventory must follow a strong disk identity across a device-node change"
        )
        let replacedNodeInventory = DiskInventory(targets: [conflictingStrongTarget])
        try expect(
            replacedNodeInventory.smartTarget(matching: originalStrongTarget) == nil,
            "fresh inventory must reject a different strong identity reusing the same device node"
        )

        let duplicateStrongIdentityOnOriginalNode = DiskTarget(
            id: "runtime-disk:/dev/disk4",
            displayName: "Cloned Disk A",
            connectionKind: .externalPhysical,
            smartSupportStatus: .supported,
            smartctlAccessProfile: SmartctlAccessProfile(devicePath: "/dev/disk4"),
            identityKey: strongIdentity
        )
        let duplicateStrongIdentityOnOtherNode = DiskTarget(
            id: "runtime-disk:/dev/disk8",
            displayName: "Cloned Disk B",
            connectionKind: .externalPhysical,
            smartSupportStatus: .supported,
            smartctlAccessProfile: SmartctlAccessProfile(devicePath: "/dev/disk8"),
            identityKey: strongIdentity
        )
        let duplicateIdentityInventory = DiskInventory(
            targets: [duplicateStrongIdentityOnOriginalNode, duplicateStrongIdentityOnOtherNode]
        )
        try expect(
            duplicateIdentityInventory.smartTarget(matching: originalStrongTarget)?.id == duplicateStrongIdentityOnOriginalNode.id,
            "duplicate strong identities may only use an exact original device-node match"
        )
        let movedDuplicateIdentityTarget = DiskTarget(
            id: "runtime-disk:/dev/disk9",
            displayName: "Cloned Disk",
            connectionKind: .externalPhysical,
            smartSupportStatus: .supported,
            smartctlAccessProfile: SmartctlAccessProfile(devicePath: "/dev/disk9"),
            identityKey: strongIdentity
        )
        try expect(
            duplicateIdentityInventory.smartTarget(matching: movedDuplicateIdentityTarget) == nil,
            "duplicate strong identities without an exact node match must be rejected as ambiguous"
        )

        var placeholderSerialSnapshot = collisionSnapshot
        placeholderSerialSnapshot.device.serialNumber = "000000000000"
        try expect(
            placeholderSerialSnapshot.effectiveDiskIdentity.rawValue == collidingWeakIdentity.rawValue,
            "placeholder serial numbers must not become a shared strong identity"
        )
    }

    private static func runDiskInventoryBasicTest() throws {
        try expect(
            DiskInventoryReader.acceptsPhysicalWholeDiskMetadata(
                isWholeDisk: true,
                mediaName: "Realtek RTL9210 NVME Media",
                mediaContent: "GUID_partition_scheme",
                mediaPath: "IODeviceTree:/usb/RTL9210",
                protocolName: "USB",
                modelName: "RTL9210 NVME"
            ),
            "physical USB whole disk should be accepted"
        )
        try expect(
            !DiskInventoryReader.acceptsPhysicalWholeDiskMetadata(
                isWholeDisk: true,
                mediaName: "AppleAPFSMedia",
                mediaContent: "EF57347C-0000-11AA-AA11-00306543ECAC",
                mediaPath: "IOService:/disk/AppleAPFSContainerScheme/AppleAPFSMedia",
                protocolName: "USB",
                modelName: "RTL9210 NVME"
            ),
            "APFS synthesized whole disk should be rejected"
        )
        try expect(
            !DiskInventoryReader.acceptsPhysicalWholeDiskMetadata(
                isWholeDisk: true,
                mediaName: "Apple UDIF Media",
                mediaContent: "GUID_partition_scheme",
                mediaPath: "IOService:/IOHDIXController",
                protocolName: "Virtual Interface",
                modelName: "Disk Image"
            ),
            "disk image whole disk should be rejected"
        )
        try expect(
            !DiskInventoryReader.acceptsPhysicalWholeDiskMetadata(
                isWholeDisk: false,
                mediaName: "External Partition",
                mediaContent: "Apple_APFS",
                mediaPath: "IODeviceTree:/usb/disk4s2",
                protocolName: "USB",
                modelName: "RTL9210 NVME"
            ),
            "partition should be rejected"
        )

        let realtekTypes = DiskInventoryReader.allowedSmartctlDeviceTypes(
            protocolName: "USB",
            modelName: "RTL9210 NVME",
            connectionKind: .externalPhysical
        )
        try expect(realtekTypes.first == .sntRealtek, "RTL9210 should prefer the fixed sntrealtek bridge type")
        try expect(realtekTypes.contains(.auto) && realtekTypes.contains(.sat), "RTL9210 should retain safe fallback types")

        let internalTypes = DiskInventoryReader.allowedSmartctlDeviceTypes(
            protocolName: "Apple Fabric",
            modelName: "APPLE SSD TEST",
            connectionKind: .internalPhysical
        )
        try expect(!internalTypes.contains(.sntRealtek), "internal disks must not receive USB bridge types")
        try expect(SmartSupportStatus.supported.rawValue == "可尝试读取 SMART", "preflight status must not promise a successful SMART read")

        let inventory = DiskInventoryReader.read()
        try expect(!inventory.targets.contains(where: { $0.devicePath?.contains("rdisk") == true }), "inventory should not expose raw rdisk targets")
        try expect(!inventory.targets.contains(where: { $0.devicePath?.range(of: #"disk\d+s\d+"#, options: .regularExpression) != nil }), "inventory should not expose partition targets for SMART")
        try expect(
            !inventory.targets.compactMap(\.identityKey?.rawValue).contains { $0.contains("<CFUUID") || $0.contains("0x") },
            "runtime disk identities must not include process-specific CFUUID pointer descriptions"
        )
    }

    private static func runHardwareProfileBasicTest() async throws {
        let profile = await HardwareProfileReader.read(showPrivateIdentifiers: false)
        try expect(profile.headlineRows.count == 4, "hardware profile should expose four headline rows")
        let sectionTitles = Set(profile.sections.map(\.title))
        try expect(sectionTitles.contains("系统软件信息"), "hardware profile missing system software section")
        try expect(sectionTitles.contains("处理器与内存"), "hardware profile missing processor section")
        try expect(sectionTitles.contains("系统硬件信息"), "hardware profile missing hardware section")
        try expect(sectionTitles.contains("内置存储"), "hardware profile missing internal storage section")
        guard let privacy = profile.sections.first(where: { $0.title == "隐私与设备标识" }) else {
            throw SelfTestFailure.failed("hardware profile missing privacy section")
        }
        try expect(privacy.rows.contains(where: { $0.title == "隐私处理" }), "hardware privacy handling row missing")
        let identifierRows = privacy.rows.filter { ["序列号", "Provisioning UDID", "平台 UUID"].contains($0.title) }
        try expect(identifierRows.count == 3, "hardware identifier rows missing")
        try expect(identifierRows.allSatisfy { row in
            !row.value.isEmpty && row.value.allSatisfy { $0 == "*" || $0 == "-" }
        }, "hardware identifiers should be masked by default")
    }

    private static func runLiveProbe(saveToHistory: Bool) async throws -> SmartSnapshot {
        let runner = SmartctlRunner()
        let outcome = await runner.readDisk0()
        switch outcome {
        case .success(let snapshot):
            try expect(snapshot.metrics.hasCoreFields, "live probe did not return core fields")
            print("Live probe: \(snapshot.device.modelName ?? snapshot.device.deviceName), \(snapshot.healthLevel.title), \(snapshot.displayReadCompleteness.rawValue), exit \(snapshot.smartctlExitStatus.map(String.init) ?? "nil")")
            if saveToHistory {
                _ = try SnapshotStore().append(snapshot)
                print("Saved live snapshot: \(snapshot.id)")
            }
            return snapshot
        case .failure(let failure):
            throw SelfTestFailure.failed("live probe failed: \(failure.title) - \(failure.message)")
        }
    }

    private static func runLiveInventoryProbe() async throws {
        let inventory = DiskInventoryReader.read()
        print("Live inventory: \(inventory.targets.count) total targets, \(inventory.smartTargets.count) SMART targets, \(inventory.speedTestTargets.count) speed-test targets")
        let runner = SmartctlRunner()
        for target in inventory.smartTargets {
            let path = target.devicePath ?? "no-device"
            print("Live target: \(path) | id=\(target.id) | identity=\(target.identityKey?.rawValue ?? "none") | source=\(target.identityKey?.source ?? "none") | model=\(target.modelName ?? "none") | size=\(target.mediaSizeBytes.map(String.init) ?? "none") | protocol=\(target.protocolName ?? "none")")
            switch await runner.read(target: target) {
            case .success(let snapshot):
                print("Live SMART success: \(path) | \(target.displayName) | \(snapshot.metrics.effectiveProtocolFamily.rawValue) | \(snapshot.healthLevel.title) | \(snapshot.displayReadCompleteness.rawValue)")
            case .failure(let failure):
                print("Live SMART unavailable: \(path) | \(target.displayName) | \(failure.title)")
            }
        }
    }

    private static func runOldSnapshotReevaluationTest() throws {
        var snapshot = try parse(exitFourSupplementalLogJSON)
        snapshot.healthLevel = .attention
        let reevaluated = snapshot.reevaluatedForDisplay()
        try expect(reevaluated.healthLevel == .healthy, "old exit 4 snapshot should display healthy")
        try expect(reevaluated.displayReadCompleteness == .coreCompleteSupplementalUnavailable, "old exit 4 snapshot should show supplemental log limitation")
    }

    private static func runLegacySnapshotDecodeTest() throws {
        let snapshot = try parse(healthyExitZeroJSON)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode([snapshot])
        guard var objects = try JSONSerialization.jsonObject(with: encoded) as? [[String: Any]],
              var legacy = objects.first,
              var device = legacy["device"] as? [String: Any],
              var metrics = legacy["metrics"] as? [String: Any] else {
            throw SelfTestFailure.failed("encoded snapshot should have the expected object structure")
        }

        ["rotationRateRPM", "ataVersion", "sataVersion", "scsiVersion"].forEach { device.removeValue(forKey: $0) }
        [
            "protocolFamily", "reallocatedSectorCount", "reallocationEventCount",
            "currentPendingSectorCount", "offlineUncorrectableSectorCount",
            "reportedUncorrectableErrors", "commandTimeoutCount", "crcErrorCount",
            "endToEndErrorCount", "ataAttributeCount", "ataFailingAttributeCount", "ataPastFailureAttributeCount",
            "scsiGrownDefectList", "scsiNonMediumErrorCount", "scsiReadUncorrectedErrors",
            "scsiWriteUncorrectedErrors", "scsiVerifyUncorrectedErrors"
        ].forEach { metrics.removeValue(forKey: $0) }
        legacy["device"] = device
        legacy["metrics"] = metrics
        legacy.removeValue(forKey: "ataAttributes")
        legacy.removeValue(forKey: "scsiErrorCounters")
        objects[0] = legacy

        let legacyData = try JSONSerialization.data(withJSONObject: objects)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([SmartSnapshot].self, from: legacyData)
        try expect(decoded.count == 1, "legacy snapshot JSON should still decode")
        try expect(decoded[0].metrics.effectiveProtocolFamily == .nvme, "legacy NVMe protocol should be inferred")
        try expect(decoded[0].device.serialNumber == "TESTSERIAL123", "legacy snapshot identity should be retained")
    }

    private static func runSerialAndExportTest() throws {
        var snapshot = try parse(healthyExitZeroJSON)
        try expect(snapshot.device.serialNumber == "TESTSERIAL123", "serial should be retained in model")
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ShixinDiskHealthSelfTest-\(UUID().uuidString)", isDirectory: true)
        let store = SnapshotStore(directory: directory)
        let snapshots = try store.append(snapshot)
        var divergentDuplicate = snapshot
        divergentDuplicate.capturedAt = snapshot.capturedAt.addingTimeInterval(1)
        try store.save([snapshot, snapshot, divergentDuplicate])
        let repairedDuplicates = try store.load()
        try expect(repairedDuplicates.count == 2, "exact duplicate SMART records must collapse without losing a divergent record")
        try expect(Set(repairedDuplicates.map(\.id)).count == 2, "divergent SMART records sharing an old UUID must receive unique IDs")
        let persistedSnapshotDecoder = JSONDecoder()
        persistedSnapshotDecoder.dateDecodingStrategy = .iso8601
        let persistedDuplicateRepair = try persistedSnapshotDecoder.decode(
            [SmartSnapshot].self,
            from: Data(contentsOf: store.snapshotsURL)
        )
        try expect(persistedDuplicateRepair.count == 2, "SMART duplicate repair must persist exactly once")
        try store.save(snapshots)
        try store.exportJSON(snapshots, to: directory.appendingPathComponent("export.json"))
        try store.exportCSV(snapshots, to: directory.appendingPathComponent("export.csv"))
        let csv = try String(contentsOf: directory.appendingPathComponent("export.csv"), encoding: .utf8)
        try expect(csv.contains("TESTSERIAL123"), "export should include retained serial number after warning")
        let csvLines = csv.split(whereSeparator: \Character.isNewline)
        try expect(csvLines.count == 2, "single snapshot CSV should contain one header and one row")
        try expect(
            csvLines[0].split(separator: ",", omittingEmptySubsequences: false).count
                == csvLines[1].split(separator: ",", omittingEmptySubsequences: false).count,
            "snapshot CSV header and data row must have matching column counts"
        )
        snapshot.device.modelName = "=HYPERLINK(\"https://example.invalid\")"
        try store.exportCSV([snapshot], to: directory.appendingPathComponent("formula-safe.csv"))
        let formulaSafeCSV = try String(contentsOf: directory.appendingPathComponent("formula-safe.csv"), encoding: .utf8)
        try expect(formulaSafeCSV.contains("'=HYPERLINK"), "CSV formula-like device values must be neutralized")
        try expect(CSVExportSanitizer.escape("\t=1+1").hasPrefix("'"), "tab-prefixed CSV formulas must be neutralized")
        try expect(CSVExportSanitizer.escape("\r=1+1").hasPrefix("\"'"), "carriage-return-prefixed CSV formulas must be neutralized")
        try expect(CSVExportSanitizer.escape("\n+1").hasPrefix("\"'"), "newline-prefixed CSV formulas must be neutralized")
        let redacted = SmartPrivacyRedactor.redactJSON(snapshot.rawJSON)
        try expect(!redacted.contains("TESTSERIAL123"), "redacted raw JSON must hide serial numbers")
        try expect(redacted.contains("<redacted>"), "redacted raw JSON should mark hidden values")

        let truncatedJSON = #"{"serial_number":"TRUNCATED-SERIAL","wwn":{"naa":5,"id":123"#
        let redactedTruncatedJSON = SmartPrivacyRedactor.redactJSON(truncatedJSON)
        try expect(!redactedTruncatedJSON.contains("TRUNCATED-SERIAL"), "truncated JSON must redact quoted serial values")
        try expect(!redactedTruncatedJSON.contains("123"), "truncated JSON must not leak a nested WWN value")

        let diagnosticText = "Serial Number: TEXT-SERIAL\nLU WWN Device Id: 5 000000 123456789"
        let redactedDiagnosticText = SmartPrivacyRedactor.redactJSON(diagnosticText)
        try expect(!redactedDiagnosticText.contains("TEXT-SERIAL"), "plain diagnostic output must redact serial values")
        try expect(!redactedDiagnosticText.contains("123456789"), "plain diagnostic output must redact WWN values")
        try expect(
            SmartPrivacyRedactor.privacySafeDisplayPath(
                "/Users/private/Applications/Test.app/Contents/Tools/smartctl",
                homeDirectory: "/Users/private"
            ) == "~/Applications/Test.app/Contents/Tools/smartctl",
            "displayed tool paths must hide the local home-directory name"
        )
        try expect(
            SmartPrivacyRedactor.privacySafeDisplayPath(
                "/Users/private-other/tool",
                homeDirectory: "/Users/private"
            ) == "/Users/private-other/tool",
            "home-path redaction must not rewrite a similar path prefix"
        )
    }

    private static func runProcessExecutorTest() async throws {
        let output = try await ProcessExecutor.run(
            executableURL: selfExecutableURL,
            arguments: ["--process-fixture"],
            timeoutSeconds: 5,
            maximumOutputBytes: 5 * 1_024 * 1_024
        )
        try expect(output.stdout.count == 2 * 1_024 * 1_024, "process stdout was not drained completely")
        try expect(output.stderr.count == 2 * 1_024 * 1_024, "process stderr was not drained completely")

        do {
            _ = try await ProcessExecutor.run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["2"],
                timeoutSeconds: 0.05
            )
            throw SelfTestFailure.failed("process timeout should throw")
        } catch ProcessExecutionError.timedOut {
            // Expected.
        }

        let outputLimitStartedAt = Date()
        do {
            _ = try await ProcessExecutor.run(
                executableURL: selfExecutableURL,
                arguments: ["--process-unbounded-fixture"],
                timeoutSeconds: 5,
                maximumOutputBytes: 1 * 1_024 * 1_024
            )
            throw SelfTestFailure.failed("process output limit should throw")
        } catch ProcessExecutionError.outputLimitExceeded {
            try expect(Date().timeIntervalSince(outputLimitStartedAt) < 2, "output-limit termination must not wait for process timeout")
        }
    }

    private static func runSpeedTestSizeOptionTest() throws {
        try expect(SpeedTestSizeOption.oneGB.bytes == 1_000_000_000, "1 GB size option is wrong")
        try expect(SpeedTestSizeOption.fiveGB.bytes == 5_000_000_000, "5 GB size option is wrong")
        try expect(SpeedTestSizeOption.tenGB.bytes == 10_000_000_000, "10 GB size option is wrong")
        try expect(SpeedTestSizeOption.fiftyGB.bytes == 50_000_000_000, "50 GB size option is wrong")
        try expect(SpeedTestSizeOption.allCases.map(\.title) == ["1 GB", "5 GB", "10 GB", "50 GB"], "speed test UI size options should be 1/5/10/50 GB")
        try expect(SpeedTestSizeOption.defaultOption == .fiveGB, "speed test default must be 5 GB")
        try expect(SmartFormatting.speedMBps(950) == "950 MB/s", "MB/s formatting failed")
        try expect(SmartFormatting.speedMBps(1_500) == "1.50 GB/s", "GB/s formatting failed")
    }

    private static func runSpeedTestPathPolicyTest() throws {
        let root = try makeTemporaryDirectory(name: "PathPolicy")
        let valid = root.appendingPathComponent("valid", isDirectory: true)
        try FileManager.default.createDirectory(at: valid, withIntermediateDirectories: true)
        _ = try SpeedTestPathPolicy.validate(directoryURL: valid)

        let file = root.appendingPathComponent("file.txt")
        FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
        try expectThrows("file path should be rejected") {
            _ = try SpeedTestPathPolicy.validate(directoryURL: file)
        }

        try expectThrows("/dev should be rejected") {
            _ = try SpeedTestPathPolicy.validate(directoryURL: URL(fileURLWithPath: "/dev"))
        }

        let fakeAppDirectory = root.appendingPathComponent("Fake.app", isDirectory: true).appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeAppDirectory, withIntermediateDirectories: true)
        try expectThrows("app bundle path should be rejected") {
            _ = try SpeedTestPathPolicy.validate(directoryURL: fakeAppDirectory)
        }

        let exactTemporaryFile = valid.appendingPathComponent("\(SpeedTestPathPolicy.testFilePrefix)\(UUID().uuidString).bin")
        FileManager.default.createFile(atPath: exactTemporaryFile.path, contents: Data())
        try expect(SpeedTestPathPolicy.canRemoveSpeedTestFile(exactTemporaryFile), "generated speed-test filename should be removable")
        let prefixOnlyFile = valid.appendingPathComponent("\(SpeedTestPathPolicy.testFilePrefix)notes.bin")
        FileManager.default.createFile(atPath: prefixOnlyFile.path, contents: Data())
        try expect(!SpeedTestPathPolicy.canRemoveSpeedTestFile(prefixOnlyFile), "prefix-only arbitrary file must not be removable")

        let locked = root.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: locked.path)
        if !FileManager.default.isWritableFile(atPath: locked.path) {
            try expectThrows("unwritable directory should be rejected") {
                _ = try SpeedTestPathPolicy.validate(directoryURL: locked)
            }
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path)
    }

    private static func runSpeedTestStoreTest() throws {
        let root = try makeTemporaryDirectory(name: "Store")
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        let store = SpeedTestStore(directory: root, cacheDirectory: cache)
        let result = sampleSpeedTestResult(targetDisplayName: "默认临时目录")
        var renamedTargetResult = result
        renamedTargetResult.targetDiskIdentity = DiskIdentityKey(rawValue: "media:speed-target", source: "disk-arbitration-media-uuid")
        renamedTargetResult.targetDisplayName = "Old Volume Name"
        var sameTargetNewName = renamedTargetResult
        sameTargetNewName.targetDisplayName = "New Volume Name"
        try expect(
            renamedTargetResult.historyGroupKey == sameTargetNewName.historyGroupKey,
            "a renamed volume with the same disk identity must remain in one speed history group"
        )
        var externalSameName = result
        externalSameName.targetConnectionKind = .externalPhysical
        externalSameName.targetDisplayName = "Shared Name"
        var networkSameName = externalSameName
        networkSameName.targetConnectionKind = .networkVolume
        try expect(
            externalSameName.historyGroupKey != networkSameName.historyGroupKey,
            "external disks and network volumes with the same display name must not share a trend group"
        )
        let results = try store.append(result)
        try expect(results.count == 1, "speed test append failed")
        let loadedResults = try store.load()
        try expect(loadedResults.first?.id == result.id, "speed test load failed")
        var divergentDuplicateResult = result
        divergentDuplicateResult.writeAverageMBps += 1
        try store.save([result, result, divergentDuplicateResult])
        let repairedDuplicateResults = try store.load()
        try expect(repairedDuplicateResults.count == 2, "exact duplicate speed records must collapse without losing a divergent record")
        try expect(Set(repairedDuplicateResults.map(\.id)).count == 2, "divergent speed records sharing an old UUID must receive unique IDs")
        let persistedSpeedDecoder = JSONDecoder()
        persistedSpeedDecoder.dateDecodingStrategy = .iso8601
        let persistedSpeedRepair = try persistedSpeedDecoder.decode(
            [SpeedTestResult].self,
            from: Data(contentsOf: store.resultsURL)
        )
        try expect(persistedSpeedRepair.count == 2, "speed duplicate repair must persist exactly once")
        try store.save([result])

        let jsonURL = root.appendingPathComponent("speed-export.json")
        let csvURL = root.appendingPathComponent("speed-export.csv")
        var legacyPathWarningResult = result
        legacyPathWarningResult.cleanupWarning = "Could not remove \(root.path)/private-speed-file.bin"
        try store.exportJSON([legacyPathWarningResult], to: jsonURL)
        try store.exportCSV([legacyPathWarningResult], to: csvURL)
        let json = try String(contentsOf: jsonURL, encoding: .utf8)
        let csv = try String(contentsOf: csvURL, encoding: .utf8)
        try expect(csv.contains("write_average_mbps"), "speed CSV header missing write_average_mbps")
        try expect(csv.contains("read_average_mbps"), "speed CSV header missing read_average_mbps")
        try expect(!json.contains(root.path), "speed JSON export must redact legacy cleanup paths")
        try expect(!csv.contains(root.path), "speed export should not include full test directory path")
        try expect(json.contains(SpeedTestPrivacy.genericCleanupWarning), "speed JSON should retain a generic cleanup warning")

        try store.save([legacyPathWarningResult])
        let migratedResults = try store.load()
        try expect(
            migratedResults.first?.cleanupWarning == SpeedTestPrivacy.genericCleanupWarning,
            "stored legacy cleanup paths must migrate to a generic warning"
        )
        let persisted = try String(contentsOf: store.resultsURL, encoding: .utf8)
        try expect(!persisted.contains(root.path), "speed history must not persist legacy cleanup paths")

        let afterDelete = try store.delete(id: result.id)
        try expect(afterDelete.isEmpty, "speed test delete failed")
    }

    private static func runPreviousVersionHistoryImportTest() throws {
        try expect(AppRuntimeConfiguration.isInternalV2, "history import self-test must use the isolated v2 namespace")
        let root = try makeTemporaryDirectory(name: "PublishedHistoryImport")

        let publishedSmartDirectory = root.appendingPathComponent("v1-smart", isDirectory: true)
        let v2SmartDirectory = root.appendingPathComponent("v2-smart", isDirectory: true)
        let publishedSmartStore = SnapshotStore(directory: publishedSmartDirectory)
        let v2SmartStore = SnapshotStore(directory: v2SmartDirectory)
        var sharedSnapshot = try parse(healthyExitZeroJSON)
        sharedSnapshot.id = UUID()
        var importedSnapshot = sharedSnapshot
        importedSnapshot.id = UUID()
        importedSnapshot.capturedAt = sharedSnapshot.capturedAt.addingTimeInterval(-60)
        var destinationOnlySnapshot = sharedSnapshot
        destinationOnlySnapshot.id = UUID()
        destinationOnlySnapshot.capturedAt = sharedSnapshot.capturedAt.addingTimeInterval(60)
        try publishedSmartStore.save([sharedSnapshot, sharedSnapshot, importedSnapshot])
        try v2SmartStore.save([sharedSnapshot, destinationOnlySnapshot])
        let publishedSmartBytesBefore = try Data(contentsOf: publishedSmartStore.snapshotsURL)

        let importedSmartCount = try v2SmartStore.importPreviousVersionHistoryIfNeeded(from: publishedSmartDirectory)
        try expect(importedSmartCount == 1, "v2 SMART import must add only missing v1 records")
        let mergedSmartHistory = try v2SmartStore.load()
        let publishedSmartBytesAfter = try Data(contentsOf: publishedSmartStore.snapshotsURL)
        let repeatedSmartImportCount = try v2SmartStore.importPreviousVersionHistoryIfNeeded(from: publishedSmartDirectory)
        try expect(mergedSmartHistory.count == 3, "SMART history migration must preserve both source-only and destination-only records")
        try expect(publishedSmartBytesAfter == publishedSmartBytesBefore, "SMART migration must leave source bytes unchanged even when the source contains duplicates")
        try expect(repeatedSmartImportCount == 0, "v2 SMART history import must run only once")

        let publishedSpeedDirectory = root.appendingPathComponent("v1-speed", isDirectory: true)
        let v2SpeedDirectory = root.appendingPathComponent("v2-speed", isDirectory: true)
        let publishedSpeedStore = SpeedTestStore(directory: publishedSpeedDirectory)
        let v2SpeedStore = SpeedTestStore(directory: v2SpeedDirectory)
        var sharedSpeedResult = sampleSpeedTestResult(targetDisplayName: "Published Internal Disk")
        sharedSpeedResult.id = UUID()
        var importedSpeedResult = sampleSpeedTestResult(targetDisplayName: "Published External Disk")
        importedSpeedResult.id = UUID()
        var destinationOnlySpeedResult = sampleSpeedTestResult(targetDisplayName: "Internal V2 Disk")
        destinationOnlySpeedResult.id = UUID()
        try publishedSpeedStore.save([sharedSpeedResult, sharedSpeedResult, importedSpeedResult])
        try v2SpeedStore.save([sharedSpeedResult, destinationOnlySpeedResult])
        let publishedSpeedBytesBefore = try Data(contentsOf: publishedSpeedStore.resultsURL)

        let importedSpeedCount = try v2SpeedStore.importPreviousVersionHistoryIfNeeded(from: publishedSpeedDirectory)
        try expect(importedSpeedCount == 1, "v2 speed import must add only missing v1 records")
        let mergedSpeedHistory = try v2SpeedStore.load()
        let publishedSpeedBytesAfter = try Data(contentsOf: publishedSpeedStore.resultsURL)
        let repeatedSpeedImportCount = try v2SpeedStore.importPreviousVersionHistoryIfNeeded(from: publishedSpeedDirectory)
        try expect(mergedSpeedHistory.count == 3, "speed history migration must preserve both source-only and destination-only records")
        try expect(publishedSpeedBytesAfter == publishedSpeedBytesBefore, "speed migration must leave source bytes unchanged even when the source contains duplicates")
        try expect(repeatedSpeedImportCount == 0, "v2 speed history import must run only once")
    }

    private static func runSpeedTestRunnerSmallFileTest() async throws {
        let root = try makeTemporaryDirectory(name: "RunnerSmall")
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        let store = SpeedTestStore(directory: root, cacheDirectory: cache)
        try store.ensureDefaultCacheDirectory()
        let runner = SpeedTestRunner(store: store)
        let configuration = SpeedTestConfiguration(
            testSizeBytes: 8 * 1_024 * 1_024,
            displaySizeLabel: "8 MB",
            mode: .single,
            targetDirectory: cache,
            targetKind: .defaultCacheDirectory,
            targetDiskDisplayName: "SelfTest Target",
            cycleIndex: 1,
            appVersion: "SelfTest",
            chunkSizeBytes: 1 * 1_024 * 1_024,
            progressIntervalSeconds: 0
        )
        let phaseRecorder = SpeedPhaseRecorder()
        let result = try await runner.run(configuration: configuration) { progress in
            phaseRecorder.append(progress)
            if progress.phase == .syncing {
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        try expect(result.writeAverageMBps > 0, "write speed should be positive")
        try expect(result.readAverageMBps > 0, "read speed should be positive")
        try expect(result.targetDisplayName == "SelfTest Target", "speed result should retain the selected disk display name")
        try expect(result.writeNoCacheApplied != nil, "write cache-control result should be recorded")
        try expect(result.readNoCacheApplied != nil, "read cache-control result should be recorded")
        try expect(result.writeSyncSucceeded != nil, "write sync result should be recorded")
        guard let syncingElapsedSeconds = phaseRecorder.syncingElapsedSeconds else {
            throw SelfTestFailure.failed("speed-test progress should retain the measured write duration")
        }
        try expect(
            abs(result.writeDurationSeconds - syncingElapsedSeconds) < 0.01,
            "sequential write duration must exclude syncing UI and durability latency"
        )
        let phases = phaseRecorder.phases
        guard let syncingIndex = phases.firstIndex(of: .syncing),
              let readingIndex = phases.firstIndex(of: .reading) else {
            throw SelfTestFailure.failed("speed-test progress should include syncing and reading phases")
        }
        try expect(syncingIndex < readingIndex, "syncing progress must be emitted before the read phase begins")
        let ledger = try store.loadIncompleteRecords()
        let hasTempFile = try containsSpeedTestTempFile(in: cache)
        try expect(ledger.isEmpty, "ledger should be empty after completed speed test")
        try expect(!hasTempFile, "test file should be removed after completed speed test")
    }

    private static func runSpeedTestCancellationCleanupTest() async throws {
        let root = try makeTemporaryDirectory(name: "RunnerCancel")
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        let store = SpeedTestStore(directory: root, cacheDirectory: cache)
        try store.ensureDefaultCacheDirectory()
        let runner = SpeedTestRunner(store: store)
        let configuration = SpeedTestConfiguration(
            testSizeBytes: 128 * 1_024 * 1_024,
            displaySizeLabel: "128 MB",
            mode: .single,
            targetDirectory: cache,
            targetKind: .defaultCacheDirectory,
            cycleIndex: 1,
            appVersion: "SelfTest",
            chunkSizeBytes: 1 * 1_024 * 1_024,
            progressIntervalSeconds: 0,
            interChunkDelayNanoseconds: 5_000_000
        )
        let task = Task {
            try await runner.run(configuration: configuration)
        }
        try await Task.sleep(nanoseconds: 15_000_000)
        task.cancel()
        do {
            _ = try await task.value
            throw SelfTestFailure.failed("cancelled speed test should not complete")
        } catch is CancellationError {
            let ledger = try store.loadIncompleteRecords()
            let hasTempFile = try containsSpeedTestTempFile(in: cache)
            try expect(ledger.isEmpty, "ledger should be empty after cancelled speed test")
            try expect(!hasTempFile, "test file should be removed after cancelled speed test")
        }
    }

    private static func runSpeedTestCrashLedgerCleanupTest() throws {
        let root = try makeTemporaryDirectory(name: "CrashLedger")
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        let store = SpeedTestStore(directory: root, cacheDirectory: cache)
        try store.ensureDefaultCacheDirectory()
        let stale = cache.appendingPathComponent("\(SpeedTestPathPolicy.testFilePrefix)\(UUID().uuidString).bin")
        let keep = cache.appendingPathComponent("keep.bin")
        FileManager.default.createFile(atPath: stale.path, contents: Data("stale".utf8))
        FileManager.default.createFile(atPath: keep.path, contents: Data("keep".utf8))
        try store.recordIncomplete(
            SpeedTestIncompleteFile(
                fileURL: stale,
                createdAt: Date(),
                expectedSizeBytes: 5,
                targetKind: .defaultCacheDirectory
            )
        )
        let notYetCreated = cache.appendingPathComponent("\(SpeedTestPathPolicy.testFilePrefix)\(UUID().uuidString).bin")
        try store.recordIncomplete(
            SpeedTestIncompleteFile(
                fileURL: notYetCreated,
                createdAt: Date(),
                expectedSizeBytes: 5,
                targetKind: .defaultCacheDirectory
            )
        )
        try store.cleanupIncompleteTests()
        try expect(!FileManager.default.fileExists(atPath: stale.path), "stale speed test file should be cleaned")
        try expect(FileManager.default.fileExists(atPath: keep.path), "non speed-test file should not be removed")
        let ledger = try store.loadIncompleteRecords()
        try expect(ledger.isEmpty, "ledger should be empty after cleanup")

        let blocked = cache.appendingPathComponent("keep.bin")
        let laterSafe = cache.appendingPathComponent("\(SpeedTestPathPolicy.testFilePrefix)\(UUID().uuidString).bin")
        FileManager.default.createFile(atPath: laterSafe.path, contents: Data("safe".utf8))
        try store.recordIncomplete(
            SpeedTestIncompleteFile(
                fileURL: blocked,
                createdAt: Date(),
                expectedSizeBytes: 4,
                targetKind: .defaultCacheDirectory
            )
        )
        try store.recordIncomplete(
            SpeedTestIncompleteFile(
                fileURL: laterSafe,
                createdAt: Date(),
                expectedSizeBytes: 4,
                targetKind: .defaultCacheDirectory
            )
        )
        try expectThrows("cleanup should report the unsafe ledger record") {
            try store.cleanupIncompleteTests()
        }
        try expect(!FileManager.default.fileExists(atPath: laterSafe.path), "a bad ledger record must not block later safe cleanup")
        let retainedLedger = try store.loadIncompleteRecords()
        try expect(retainedLedger.count == 1, "only the failed cleanup record should remain in the ledger")
        try expect(retainedLedger.first?.fileURL == blocked, "the retained ledger record should identify the failed item")
    }

    private static func parse(_ json: String) throws -> SmartSnapshot {
        try SmartctlParser.parse(
            data: Data(json.utf8),
            readMode: .homebrewAppleSilicon,
            smartctlPath: "/opt/homebrew/bin/smartctl",
            processExitStatus: nil
        )
    }

    private static func makeTemporaryDirectory(name: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ShixinDiskHealthSelfTest-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static var selfExecutableURL: URL {
        Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0], relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
                .standardizedFileURL
    }

    private static func containsSpeedTestTempFile(in directory: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: directory.path) else { return false }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .contains { $0.hasPrefix(SpeedTestPathPolicy.testFilePrefix) }
    }

    private static func sampleSpeedTestResult(targetDisplayName: String) -> SpeedTestResult {
        let start = Date()
        return SpeedTestResult(
            startedAt: start,
            completedAt: start.addingTimeInterval(3),
            mode: .single,
            cycleIndex: 1,
            testSizeBytes: 8 * 1_024 * 1_024,
            writeAverageMBps: 1_200,
            writePeakMBps: 1_320,
            readAverageMBps: 2_100,
            readPeakMBps: 2_260,
            writeDurationSeconds: 1.4,
            readDurationSeconds: 1.1,
            targetKind: .defaultCacheDirectory,
            targetDisplayName: targetDisplayName,
            volumeName: "TestVolume",
            volumeAvailableBeforeBytes: 100_000_000_000,
            volumeAvailableAfterBytes: 99_990_000_000,
            appVersion: "SelfTest",
            runnerVersion: SpeedTestRunner.runnerVersion
        )
    }

    private static func modifiedJSON(_ json: String, replacements: [String: String]) -> String {
        replacements.reduce(json) { partial, item in
            partial.replacingOccurrences(of: item.key, with: item.value)
        }
    }

    private static let healthyExitZeroJSON = """
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

    private static let exitFourSupplementalLogJSON = healthyExitZeroJSON
        .replacingOccurrences(of: "\"exit_status\": 0", with: """
        "messages": [
          {"string": "Read 1 entries from Error Information Log failed: GetLogPage failed: system=0x38, sub=0x0, code=745", "severity": "error"}
        ],
        "exit_status": 4
        """)
        .replacingOccurrences(of: "\"percentage_used\": 2", with: "\"percentage_used\": 0")
        .replacingOccurrences(of: "\"temperature\": 45", with: "\"temperature\": 38")

    private static let healthyATAJSON = #"""
    {
      "smartctl": {"version": [7, 5], "exit_status": 0},
      "local_time": {"time_t": 1782427585},
      "device": {"name": "/dev/disk4", "type": "sat", "protocol": "ATA"},
      "model_name": "SATA SSD TEST",
      "serial_number": "ATA-SERIAL-TEST",
      "firmware_version": "2.0",
      "ata_version": {"string": "ACS-4"},
      "sata_version": {"string": "SATA 3.3"},
      "rotation_rate": 0,
      "smart_status": {"passed": true},
      "temperature": {"current": 37},
      "power_on_time": {"hours": 1234},
      "power_cycle_count": 88,
      "ata_smart_error_log": {"summary": {"count": 0}},
      "ata_smart_attributes": {
        "revision": 16,
        "table": [
          {"id":5,"name":"Reallocated_Sector_Ct","value":100,"worst":100,"thresh":10,"when_failed":"","raw":{"value":0,"string":"0"}},
          {"id":9,"name":"Power_On_Hours","value":99,"worst":99,"thresh":0,"when_failed":"","raw":{"value":1234,"string":"1234"}},
          {"id":187,"name":"Reported_Uncorrect","value":100,"worst":100,"thresh":0,"when_failed":"","raw":{"value":0,"string":"0"}},
          {"id":188,"name":"Command_Timeout","value":100,"worst":100,"thresh":0,"when_failed":"","raw":{"value":0,"string":"0"}},
          {"id":194,"name":"Temperature_Celsius","value":63,"worst":60,"thresh":0,"when_failed":"","raw":{"value":37,"string":"37"}},
          {"id":197,"name":"Current_Pending_Sector","value":100,"worst":100,"thresh":0,"when_failed":"","raw":{"value":0,"string":"0"}},
          {"id":198,"name":"Offline_Uncorrectable","value":100,"worst":100,"thresh":0,"when_failed":"","raw":{"value":0,"string":"0"}},
          {"id":199,"name":"UDMA_CRC_Error_Count","value":200,"worst":200,"thresh":0,"when_failed":"","raw":{"value":0,"string":"0"}},
          {"id":202,"name":"Percent_Lifetime_Remain","value":92,"worst":92,"thresh":1,"when_failed":"","raw":{"value":92,"string":"92"}}
        ]
      }
    }
    """#

    private static let healthySCSIJSON = #"""
    {
      "smartctl": {"version": [7, 5], "exit_status": 0},
      "local_time": {"time_t": 1782427585},
      "device": {"name": "/dev/disk5", "type": "scsi", "protocol": "SCSI"},
      "model_name": "SCSI DISK TEST",
      "serial_number": "SCSI-SERIAL-TEST",
      "firmware_version": "3.0",
      "scsi_version": "SPC-5",
      "smart_status": {"passed": true},
      "temperature": {"current": 31},
      "power_on_time": {"hours": 4321},
      "scsi_grown_defect_list": 0,
      "scsi_error_counter_log": {
        "read": {"errors_corrected_by_eccfast": 10, "total_errors_corrected": 10, "gigabytes_processed": 1200.5, "total_uncorrected_errors": 0},
        "write": {"errors_corrected_by_eccfast": 2, "total_errors_corrected": 2, "gigabytes_processed": 800.25, "total_uncorrected_errors": 0},
        "verify": {"errors_corrected_by_eccfast": 0, "total_errors_corrected": 0, "gigabytes_processed": 50.0, "total_uncorrected_errors": 0},
        "non_medium_error": {"count": 0}
      }
    }
    """#
}

private extension String {
    func replacingOccurrences(of target: String, with replacement: String, maxReplacements: Int) -> String {
        guard maxReplacements > 0, let range = range(of: target) else { return self }
        return replacingCharacters(in: range, with: replacement)
    }
}

private final class SpeedPhaseRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedProgress: [SpeedTestProgress] = []

    func append(_ progress: SpeedTestProgress) {
        lock.lock()
        storedProgress.append(progress)
        lock.unlock()
    }

    var phases: [SpeedTestPhase] {
        lock.lock()
        defer { lock.unlock() }
        return storedProgress.map(\.phase)
    }

    var syncingElapsedSeconds: TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        return storedProgress.first { $0.phase == .syncing }?.elapsedSeconds
    }
}
