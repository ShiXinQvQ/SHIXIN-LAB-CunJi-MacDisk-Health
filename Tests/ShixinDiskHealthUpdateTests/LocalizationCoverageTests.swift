import XCTest
@testable import ShixinDiskHealth
@testable import ShixinDiskHealthCore

/// The core library writes Chinese sentences and the interface translates
/// them through `L10n.t`: first by exact key, then by the regular-expression
/// rules for sentences with numbers. A reworded sentence silently falls back
/// to Chinese in English and Japanese, so every sentence the core can produce
/// must resolve in both tables.
final class LocalizationCoverageTests: XCTestCase {
    func testEveryHealthAndReadingSentenceIsTranslated() throws {
        try assertTranslated(Self.coreSentences())
    }

    func testStoredEnumTitlesShownInTheInterfaceAreTranslated() throws {
        var titles: [String] = []
        titles += HealthLevel.allCases.flatMap { [$0.title, $0.shortDescription] }
        titles += ReadCompleteness.allCases.flatMap { [$0.title, $0.shortDescription] }
        titles += ReadMode.allCases.map(\.title)
        titles += DiskConnectionKind.allCases.map(\.title)
        titles += SpeedTestMode.allCases.map(\.title)
        titles += SpeedTestTargetKind.allCases.map(\.title)
        try assertTranslated(titles)
    }

    private func assertTranslated(_ sentences: [String], file: StaticString = #filePath, line: UInt = #line) throws {
        let chinese = sentences.filter { $0.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } }
        XCTAssertFalse(chinese.isEmpty, file: file, line: line)
        for locale in ["en", "ja"] {
            let table = try Self.strings(locale)
            for sentence in Set(chinese).sorted() {
                XCTAssertTrue(Self.resolves(sentence, in: table), "\(locale) has no translation for: \(sentence)", file: file, line: line)
            }
        }
    }

    private static func resolves(_ sentence: String, in table: [String: String]) -> Bool {
        if table[sentence] != nil { return true }
        return L10n.dynamicRules.contains { rule in
            guard let expression = try? NSRegularExpression(pattern: rule.pattern) else { return false }
            let range = NSRange(sentence.startIndex..<sentence.endIndex, in: sentence)
            return expression.firstMatch(in: sentence, range: range) != nil && table[rule.localizationKey] != nil
        }
    }

    private static func strings(_ locale: String) throws -> [String: String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ShixinDiskHealth/Resources/\(locale).lproj/Localizable.strings")
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
    }

    /// Drives every branch of the health and read-completeness evaluation.
    private static func coreSentences() -> [String] {
        let nvme = SmartHealthMetrics(
            protocolFamily: .nvme, smartPassed: true, criticalWarning: 0, temperatureCelsius: 40,
            availableSparePercent: 100, availableSpareThresholdPercent: 10, percentageUsed: 2,
            mediaErrors: 0, errorLogEntries: 0
        )
        let ata = SmartHealthMetrics(
            protocolFamily: .ata, smartPassed: true, temperatureCelsius: 40,
            reallocatedSectorCount: 0, currentPendingSectorCount: 0, offlineUncorrectableSectorCount: 0,
            ataAttributeCount: 12, ataFailingAttributeCount: 0, ataPastFailureAttributeCount: 0
        )
        let scsi = SmartHealthMetrics(
            protocolFamily: .scsi, smartPassed: true, temperatureCelsius: 40,
            scsiReadUncorrectedErrors: 0, scsiWriteUncorrectedErrors: 0, scsiVerifyUncorrectedErrors: 0,
            scsiErrorCounterAvailable: true
        )
        let generic = SmartHealthMetrics(protocolFamily: .unknown, smartPassed: true, temperatureCelsius: 40)

        func variant(_ base: SmartHealthMetrics, _ change: (inout SmartHealthMetrics) -> Void) -> SmartHealthMetrics {
            var copy = base
            change(&copy)
            return copy
        }

        var cases: [(SmartHealthMetrics, ReadCompleteness, Int32?)] = [
            (nvme, .complete, 0), (ata, .complete, 0), (scsi, .complete, 0), (generic, .complete, 0),
            (SmartHealthMetrics(protocolFamily: .nvme), .failed, nil),
            (nvme, .failed, 0),
            (nvme, .complete, 1 << 3), (nvme, .complete, 1 << 4), (nvme, .complete, 1 << 5),
            (nvme, .complete, 1 << 6), (nvme, .complete, 1 << 7)
        ]
        let nvmeVariants: [(inout SmartHealthMetrics) -> Void] = [
            { $0.smartPassed = false }, { $0.criticalWarning = 1 },
            { $0.availableSparePercent = 5 }, { $0.availableSparePercent = 13 },
            { $0.mediaErrors = 3 }, { $0.temperatureCelsius = 85 }, { $0.temperatureCelsius = 70 },
            { $0.percentageUsed = 85 }
        ]
        let ataVariants: [(inout SmartHealthMetrics) -> Void] = [
            { $0.ataFailingAttributeCount = 2 }, { $0.currentPendingSectorCount = 1 },
            { $0.offlineUncorrectableSectorCount = 1 }, { $0.reportedUncorrectableErrors = 1 },
            { $0.endToEndErrorCount = 1 }, { $0.reallocatedSectorCount = 1 }, { $0.reallocationEventCount = 1 },
            { $0.commandTimeoutCount = 1 }, { $0.crcErrorCount = 1 }, { $0.ataPastFailureAttributeCount = 1 }
        ]
        let scsiVariants: [(inout SmartHealthMetrics) -> Void] = [
            { $0.scsiReadUncorrectedErrors = 2 }, { $0.scsiGrownDefectList = 1 }, { $0.scsiNonMediumErrorCount = 1 }
        ]
        cases += nvmeVariants.map { (variant(nvme, $0), .complete, 0) }
        cases += ataVariants.map { (variant(ata, $0), .complete, 0) }
        cases += scsiVariants.map { (variant(scsi, $0), .complete, 0) }
        cases.append((variant(generic) { $0.mediaErrors = 4 }, .complete, 0))

        var sentences: [String] = []
        for (metrics, completeness, status) in cases {
            sentences += HealthEvaluator.evaluate(metrics: metrics, readCompleteness: completeness, smartctlExitStatus: status).reasons
        }

        let supplemental = [SmartctlMessage(severity: "error", message: "Read Error Information Log failed")]
        for (metrics, messages, status) in [
            (nvme, [SmartctlMessage](), Int32(0)), (nvme, [], 4), (nvme, supplemental, 4), (nvme, [], 64),
            (SmartHealthMetrics(protocolFamily: .nvme), [], 0),
            (SmartHealthMetrics(protocolFamily: .nvme, smartPassed: true), [], 0)
        ] as [(SmartHealthMetrics, [SmartctlMessage], Int32)] {
            sentences += HealthEvaluator.readCompleteness(metrics: metrics, messages: messages, exitStatus: status).reasons
        }
        return sentences
    }
}
