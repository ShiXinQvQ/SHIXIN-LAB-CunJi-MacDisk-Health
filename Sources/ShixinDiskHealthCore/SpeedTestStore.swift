import Foundation

public final class SpeedTestStore: @unchecked Sendable {
    private static let publishedImportMarkerName = ".v1-speed-history-imported"
    private static let internalV2ImportMarkerName = ".v2-speed-history-imported"

    public let appSupportDirectory: URL
    public let resultsURL: URL
    public let incompleteURL: URL
    public let defaultCacheDirectory: URL

    public init(fileManager: FileManager = .default) {
        let supportBase = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let cacheBase = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches")
        self.appSupportDirectory = supportBase.appendingPathComponent(AppRuntimeConfiguration.appSupportDirectoryName, isDirectory: true)
        self.resultsURL = appSupportDirectory.appendingPathComponent("speed-tests.json")
        self.incompleteURL = appSupportDirectory.appendingPathComponent("speed-test-incomplete.json")
        self.defaultCacheDirectory = cacheBase
            .appendingPathComponent(AppRuntimeConfiguration.speedTestCacheDirectoryName, isDirectory: true)
            .appendingPathComponent("SpeedTest", isDirectory: true)
    }

    public init(directory: URL, cacheDirectory: URL? = nil) {
        self.appSupportDirectory = directory
        self.resultsURL = directory.appendingPathComponent("speed-tests.json")
        self.incompleteURL = directory.appendingPathComponent("speed-test-incomplete.json")
        self.defaultCacheDirectory = (cacheDirectory ?? directory.appendingPathComponent("SpeedTestCache", isDirectory: true))
    }

    public func ensureDefaultCacheDirectory() throws {
        try FileManager.default.createDirectory(at: defaultCacheDirectory, withIntermediateDirectories: true)
    }

    public func load() throws -> [SpeedTestResult] {
        let decoded = try decodedResults()
        let normalized = Self.normalizedUniqueIDs(privacySafeResults(decoded))
        if normalized != decoded {
            try save(normalized)
        }
        return normalized.sorted { $0.completedAt > $1.completedAt }
    }

    public func save(_ results: [SpeedTestResult]) throws {
        try FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        let safeResults = privacySafeResults(results).sorted { $0.completedAt > $1.completedAt }
        let data = try JSONEncoder.speedTestEncoder.encode(safeResults)
        try data.write(to: resultsURL, options: [.atomic])
    }

    public func append(_ result: SpeedTestResult) throws -> [SpeedTestResult] {
        var results = try load()
        results.insert(result, at: 0)
        try save(results)
        return results
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
        let sourceURL = previousDirectory.appendingPathComponent("speed-tests.json")
        guard fileManager.fileExists(atPath: sourceURL.path) else { return 0 }
        guard sourceURL.standardizedFileURL != resultsURL.standardizedFileURL else { return 0 }

        let previousResults = try SpeedTestStore(directory: previousDirectory).loadForImport()
        let normalizedMerge = Self.normalizedUniqueIDs(merged + previousResults)
        let additionCount = normalizedMerge.count - merged.count
        if normalizedMerge != merged {
            merged = normalizedMerge
            try save(merged)
        }

        try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        let markerText = "Merged missing speed-test history from \(sourceDirectoryName); source remained unchanged.\n"
        try Data(markerText.utf8).write(to: markerURL, options: [.atomic])
        return additionCount
    }

    public func delete(id: SpeedTestResult.ID) throws -> [SpeedTestResult] {
        let results = try load().filter { $0.id != id }
        try save(results)
        return results
    }

    public func exportJSON(_ results: [SpeedTestResult], to destination: URL) throws {
        let safeResults = privacySafeResults(results).sorted { $0.completedAt > $1.completedAt }
        let data = try JSONEncoder.speedTestEncoder.encode(safeResults)
        try data.write(to: destination, options: [.atomic])
    }

    public func exportCSV(_ results: [SpeedTestResult], to destination: URL) throws {
        let header = [
            "started_at",
            "completed_at",
            "mode",
            "cycle_index",
            "test_size_bytes",
            "test_size_gb",
            "write_average_mbps",
            "write_peak_mbps",
            "read_average_mbps",
            "read_peak_mbps",
            "write_duration_seconds",
            "read_duration_seconds",
            "target_kind",
            "target_display_name",
            "target_connection_kind",
            "target_disk_identity",
            "volume_name",
            "volume_available_before_bytes",
            "volume_available_after_bytes",
            "app_version",
            "runner_version",
            "cleanup_warning",
            "write_no_cache_applied",
            "read_no_cache_applied",
            "write_sync_succeeded",
            "measurement_warnings"
        ]
        let rows = privacySafeResults(results).sorted { $0.completedAt > $1.completedAt }.map(csvRow)
        let csv = ([header.map(CSVExportSanitizer.escape).joined(separator: ",")] + rows).joined(separator: "\n") + "\n"
        guard let data = csv.data(using: String.Encoding.utf8) else { return }
        try data.write(to: destination, options: Data.WritingOptions.atomic)
    }

    public func recordIncomplete(_ record: SpeedTestIncompleteFile) throws {
        try FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        var records = try loadIncompleteRecords()
        records.removeAll { $0.fileURL.standardizedFileURL.path == record.fileURL.standardizedFileURL.path }
        records.append(record)
        try saveIncompleteRecords(records)
    }

    public func removeIncomplete(fileURL: URL) throws {
        var records = try loadIncompleteRecords()
        records.removeAll { $0.fileURL.standardizedFileURL.path == fileURL.standardizedFileURL.path }
        try saveIncompleteRecords(records)
    }

    public func loadIncompleteRecords() throws -> [SpeedTestIncompleteFile] {
        guard FileManager.default.fileExists(atPath: incompleteURL.path) else {
            return []
        }
        let data = try Data(contentsOf: incompleteURL)
        return try JSONDecoder.speedTestDecoder.decode([SpeedTestIncompleteFile].self, from: data)
    }

    public func cleanupIncompleteTests() throws {
        let records = try loadIncompleteRecords()
        var remainingRecords: [SpeedTestIncompleteFile] = []
        var firstFailure: Error?
        for record in records {
            do {
                try removeSpeedTestFileIfAllowed(record.fileURL)
            } catch {
                remainingRecords.append(record)
                if firstFailure == nil {
                    firstFailure = error
                }
            }
        }
        try saveIncompleteRecords(remainingRecords)
        do {
            try cleanupOldDefaultCacheFiles()
        } catch {
            if firstFailure == nil {
                firstFailure = error
            }
        }
        if let firstFailure {
            throw firstFailure
        }
    }

    public func cleanupOldDefaultCacheFiles(olderThan interval: TimeInterval = 24 * 60 * 60) throws {
        guard FileManager.default.fileExists(atPath: defaultCacheDirectory.path) else { return }
        let cutoff = Date().addingTimeInterval(-interval)
        let urls = try FileManager.default.contentsOfDirectory(
            at: defaultCacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: []
        )
        for url in urls where url.lastPathComponent.hasPrefix(SpeedTestPathPolicy.testFilePrefix) {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            if (values?.contentModificationDate ?? .distantPast) < cutoff {
                try removeSpeedTestFileIfAllowed(url)
            }
        }
    }

    private func saveIncompleteRecords(_ records: [SpeedTestIncompleteFile]) throws {
        try FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        if records.isEmpty {
            if FileManager.default.fileExists(atPath: incompleteURL.path) {
                try FileManager.default.removeItem(at: incompleteURL)
            }
            return
        }
        let data = try JSONEncoder.speedTestEncoder.encode(records.sorted { $0.createdAt > $1.createdAt })
        try data.write(to: incompleteURL, options: [.atomic])
    }

    private func removeSpeedTestFileIfAllowed(_ fileURL: URL) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        guard SpeedTestPathPolicy.canRemoveSpeedTestFile(fileURL) else {
            throw SpeedTestFailure(
                title: "残留文件清理被拒绝",
                message: "目标文件不符合速度测试临时文件安全规则。",
                recovery: "请手动检查该路径，App 不会删除非速度测试临时文件。"
            )
        }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func privacySafeResults(_ results: [SpeedTestResult]) -> [SpeedTestResult] {
        results.map { result in
            var copy = result
            if let warning = copy.cleanupWarning, !warning.isEmpty {
                copy.cleanupWarning = SpeedTestPrivacy.genericCleanupWarning
            }
            return copy
        }
    }

    private func csvRow(for result: SpeedTestResult) -> String {
        let values: [String] = [
            ISO8601DateFormatter().string(from: result.startedAt),
            ISO8601DateFormatter().string(from: result.completedAt),
            result.mode.rawValue,
            String(result.cycleIndex),
            String(result.testSizeBytes),
            String(format: "%.2f", Double(result.testSizeBytes) / 1_000_000_000),
            String(format: "%.2f", result.writeAverageMBps),
            String(format: "%.2f", result.writePeakMBps),
            String(format: "%.2f", result.readAverageMBps),
            String(format: "%.2f", result.readPeakMBps),
            String(format: "%.3f", result.writeDurationSeconds),
            String(format: "%.3f", result.readDurationSeconds),
            result.targetKind.rawValue,
            result.targetDisplayName,
            result.targetConnectionKind?.rawValue ?? "",
            result.targetDiskIdentity?.rawValue ?? "",
            result.volumeName ?? "",
            result.volumeAvailableBeforeBytes.map(String.init) ?? "",
            result.volumeAvailableAfterBytes.map(String.init) ?? "",
            result.appVersion,
            result.runnerVersion,
            result.cleanupWarning ?? "",
            result.writeNoCacheApplied.map(String.init) ?? "",
            result.readNoCacheApplied.map(String.init) ?? "",
            result.writeSyncSucceeded.map(String.init) ?? "",
            result.measurementWarnings?.joined(separator: " | ") ?? ""
        ]
        return values.map(CSVExportSanitizer.escape).joined(separator: ",")
    }

    private static func defaultDirectory(named directoryName: String, fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    private func loadForImport() throws -> [SpeedTestResult] {
        Self.normalizedUniqueIDs(privacySafeResults(try decodedResults()))
            .sorted { $0.completedAt > $1.completedAt }
    }

    private func decodedResults() throws -> [SpeedTestResult] {
        guard FileManager.default.fileExists(atPath: resultsURL.path) else {
            return []
        }
        let data = try Data(contentsOf: resultsURL)
        return try JSONDecoder.speedTestDecoder.decode([SpeedTestResult].self, from: data)
    }

    private static func normalizedUniqueIDs(_ results: [SpeedTestResult]) -> [SpeedTestResult] {
        var normalized: [SpeedTestResult] = []
        var recordsByOriginalID: [SpeedTestResult.ID: [SpeedTestResult]] = [:]
        var usedIDs: Set<SpeedTestResult.ID> = []

        for original in results {
            var result = original
            let originalID = original.id
            let existingRecords = recordsByOriginalID[originalID, default: []]
            if existingRecords.contains(where: { recordsMatchIgnoringID($0, original) }) {
                continue
            }
            if !existingRecords.isEmpty || usedIDs.contains(result.id) {
                repeat {
                    result.id = UUID()
                } while usedIDs.contains(result.id)
            }
            recordsByOriginalID[originalID, default: []].append(original)
            usedIDs.insert(result.id)
            normalized.append(result)
        }
        return normalized
    }

    private static func recordsMatchIgnoringID(_ lhs: SpeedTestResult, _ rhs: SpeedTestResult) -> Bool {
        var normalizedLeft = lhs
        normalizedLeft.id = rhs.id
        return normalizedLeft == rhs
    }
}

extension JSONEncoder {
    static var speedTestEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var speedTestDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
