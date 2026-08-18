import Foundation

public final class SnapshotStore {
    private static let publishedImportMarkerName = ".v1-smart-history-imported"
    private static let internalV2ImportMarkerName = ".v2-smart-history-imported"

    public let appSupportDirectory: URL
    public let snapshotsURL: URL

    public init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        self.appSupportDirectory = base.appendingPathComponent(AppRuntimeConfiguration.appSupportDirectoryName, isDirectory: true)
        self.snapshotsURL = appSupportDirectory.appendingPathComponent("snapshots.json")
    }

    public init(directory: URL) {
        self.appSupportDirectory = directory
        self.snapshotsURL = directory.appendingPathComponent("snapshots.json")
    }

    public func load() throws -> [SmartSnapshot] {
        let decoded = try decodedSnapshots()
        let normalized = Self.normalizedUniqueIDs(decoded)
        if normalized != decoded {
            try save(normalized)
        }
        return normalized
    }

    public func save(_ snapshots: [SmartSnapshot]) throws {
        try FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder.snapshotEncoder.encode(snapshots.sorted { $0.capturedAt > $1.capturedAt })
        try data.write(to: snapshotsURL, options: [.atomic])
    }

    public func append(_ snapshot: SmartSnapshot) throws -> [SmartSnapshot] {
        var snapshots = try load()
        snapshots.insert(snapshot, at: 0)
        try save(snapshots)
        return snapshots
    }

    @discardableResult
    public func importPreviousVersionHistoryIfNeeded(
        from sourceDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> Int {
        guard let sourceDirectoryName = AppRuntimeConfiguration.previousVersionAppSupportDirectoryName else {
            return 0
        }

        var merged = try load()

        let markerName = AppRuntimeConfiguration.isInternalV2
            ? Self.publishedImportMarkerName
            : Self.internalV2ImportMarkerName
        let markerURL = appSupportDirectory.appendingPathComponent(markerName)
        guard !fileManager.fileExists(atPath: markerURL.path) else { return 0 }

        let previousDirectory = sourceDirectory
            ?? Self.defaultDirectory(named: sourceDirectoryName, fileManager: fileManager)
        let sourceURL = previousDirectory.appendingPathComponent("snapshots.json")
        guard fileManager.fileExists(atPath: sourceURL.path) else { return 0 }
        guard sourceURL.standardizedFileURL != snapshotsURL.standardizedFileURL else { return 0 }

        let previousSnapshots = try SnapshotStore(directory: previousDirectory).loadForImport()
        let normalizedMerge = Self.normalizedUniqueIDs(merged + previousSnapshots)
        let additionCount = normalizedMerge.count - merged.count
        if normalizedMerge != merged {
            merged = normalizedMerge
            try save(merged)
        }

        try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        let markerText = "Merged missing SMART history from \(sourceDirectoryName); source remained unchanged.\n"
        try Data(markerText.utf8).write(to: markerURL, options: [.atomic])
        return additionCount
    }

    public func delete(id: SmartSnapshot.ID) throws -> [SmartSnapshot] {
        let snapshots = try load().filter { $0.id != id }
        try save(snapshots)
        return snapshots
    }

    public func exportJSON(_ snapshots: [SmartSnapshot], to destination: URL) throws {
        let data = try JSONEncoder.snapshotEncoder.encode(snapshots.sorted { $0.capturedAt > $1.capturedAt })
        try data.write(to: destination, options: [.atomic])
    }

    public func exportCSV(_ snapshots: [SmartSnapshot], to destination: URL) throws {
        let header = [
            "captured_at",
            "disk_identity",
            "disk_identity_source",
            "disk_display_name",
            "disk_connection_kind",
            "disk_device_path",
            "model",
            "serial_number",
            "firmware",
            "protocol_family",
            "health_level",
            "smart_passed",
            "temperature_celsius",
            "percentage_used",
            "available_spare_percent",
            "available_spare_threshold_percent",
            "data_units_read",
            "data_units_written",
            "read_bytes",
            "written_bytes",
            "power_on_hours",
            "power_cycles",
            "unsafe_shutdowns",
            "media_errors",
            "error_log_entries",
            "reallocated_sector_count",
            "reallocation_event_count",
            "current_pending_sector_count",
            "offline_uncorrectable_sector_count",
            "reported_uncorrectable_errors",
            "command_timeout_count",
            "crc_error_count",
            "end_to_end_error_count",
            "scsi_grown_defect_list",
            "scsi_non_medium_error_count",
            "scsi_read_uncorrected_errors",
            "scsi_write_uncorrected_errors",
            "scsi_verify_uncorrected_errors",
            "ata_smart_attributes",
            "ata_failing_attribute_count",
            "ata_past_failure_attribute_count",
            "smartctl_exit_status",
            "read_mode"
        ]
        let sortedSnapshots = snapshots.sorted { $0.capturedAt > $1.capturedAt }
        let rows = sortedSnapshots.map(csvRow)
        let csv = ([header.map(CSVExportSanitizer.escape).joined(separator: ",")] + rows).joined(separator: "\n") + "\n"
        guard let data = csv.data(using: String.Encoding.utf8) else { return }
        try data.write(to: destination, options: Data.WritingOptions.atomic)
    }

    private func csvRow(for snapshot: SmartSnapshot) -> String {
        let values: [String] = [
            ISO8601DateFormatter().string(from: snapshot.capturedAt),
            snapshot.effectiveDiskIdentity.rawValue,
            snapshot.effectiveDiskIdentity.source,
            snapshot.diskDisplayName ?? "",
            snapshot.diskConnectionKind?.rawValue ?? "",
            snapshot.diskDevicePath ?? snapshot.device.deviceName,
            snapshot.device.modelName ?? "",
            snapshot.device.serialNumber ?? "",
            snapshot.device.firmwareVersion ?? "",
            snapshot.metrics.effectiveProtocolFamily.rawValue,
            snapshot.healthLevel.title,
            snapshot.metrics.smartPassed.map { String($0) } ?? "",
            snapshot.metrics.temperatureCelsius.map { String($0) } ?? "",
            snapshot.metrics.percentageUsed.map { String($0) } ?? "",
            snapshot.metrics.availableSparePercent.map { String($0) } ?? "",
            snapshot.metrics.availableSpareThresholdPercent.map { String($0) } ?? "",
            snapshot.metrics.dataUnitsRead.map { String($0) } ?? "",
            snapshot.metrics.dataUnitsWritten.map { String($0) } ?? "",
            snapshot.metrics.readBytes.map { String($0) } ?? "",
            snapshot.metrics.writtenBytes.map { String($0) } ?? "",
            snapshot.metrics.powerOnHours.map { String($0) } ?? "",
            snapshot.metrics.powerCycles.map { String($0) } ?? "",
            snapshot.metrics.unsafeShutdowns.map { String($0) } ?? "",
            snapshot.metrics.mediaErrors.map { String($0) } ?? "",
            snapshot.metrics.errorLogEntries.map { String($0) } ?? "",
            snapshot.metrics.reallocatedSectorCount.map(String.init) ?? "",
            snapshot.metrics.reallocationEventCount.map(String.init) ?? "",
            snapshot.metrics.currentPendingSectorCount.map(String.init) ?? "",
            snapshot.metrics.offlineUncorrectableSectorCount.map(String.init) ?? "",
            snapshot.metrics.reportedUncorrectableErrors.map(String.init) ?? "",
            snapshot.metrics.commandTimeoutCount.map(String.init) ?? "",
            snapshot.metrics.crcErrorCount.map(String.init) ?? "",
            snapshot.metrics.endToEndErrorCount.map(String.init) ?? "",
            snapshot.metrics.scsiGrownDefectList.map(String.init) ?? "",
            snapshot.metrics.scsiNonMediumErrorCount.map(String.init) ?? "",
            snapshot.metrics.scsiReadUncorrectedErrors.map(String.init) ?? "",
            snapshot.metrics.scsiWriteUncorrectedErrors.map(String.init) ?? "",
            snapshot.metrics.scsiVerifyUncorrectedErrors.map(String.init) ?? "",
            snapshot.ataAttributes?.map { attribute in
                let raw = attribute.rawString ?? attribute.rawValue.map(String.init) ?? ""
                return "\(attribute.id):\(attribute.name):\(raw)"
            }.joined(separator: " | ") ?? "",
            snapshot.metrics.ataFailingAttributeCount.map(String.init) ?? "",
            snapshot.metrics.ataPastFailureAttributeCount.map(String.init) ?? "",
            snapshot.smartctlExitStatus.map { String($0) } ?? "",
            snapshot.readMode.rawValue
        ]
        return values.map(CSVExportSanitizer.escape).joined(separator: ",")
    }

    private static func defaultDirectory(named directoryName: String, fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    private func loadForImport() throws -> [SmartSnapshot] {
        Self.normalizedUniqueIDs(try decodedSnapshots())
    }

    private func decodedSnapshots() throws -> [SmartSnapshot] {
        guard FileManager.default.fileExists(atPath: snapshotsURL.path) else {
            return []
        }
        let data = try Data(contentsOf: snapshotsURL)
        return try JSONDecoder.snapshotDecoder.decode([SmartSnapshot].self, from: data)
            .map { $0.reevaluatedForDisplay() }
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    private static func normalizedUniqueIDs(_ snapshots: [SmartSnapshot]) -> [SmartSnapshot] {
        var normalized: [SmartSnapshot] = []
        var recordsByOriginalID: [SmartSnapshot.ID: [SmartSnapshot]] = [:]
        var usedIDs: Set<SmartSnapshot.ID> = []

        for original in snapshots {
            var snapshot = original
            let originalID = original.id
            let existingRecords = recordsByOriginalID[originalID, default: []]
            if existingRecords.contains(where: { recordsMatchIgnoringID($0, original) }) {
                continue
            }
            if !existingRecords.isEmpty || usedIDs.contains(snapshot.id) {
                repeat {
                    snapshot.id = UUID()
                } while usedIDs.contains(snapshot.id)
            }
            recordsByOriginalID[originalID, default: []].append(original)
            usedIDs.insert(snapshot.id)
            normalized.append(snapshot)
        }
        return normalized
    }

    private static func recordsMatchIgnoringID(_ lhs: SmartSnapshot, _ rhs: SmartSnapshot) -> Bool {
        var normalizedLeft = lhs
        normalizedLeft.id = rhs.id
        return normalizedLeft == rhs
    }
}

extension JSONEncoder {
    static var snapshotEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var snapshotDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
