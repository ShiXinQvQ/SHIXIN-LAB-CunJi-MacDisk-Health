import Foundation

public enum SmartctlParserError: Error, LocalizedError, Sendable {
    case nonJSON
    case missingCoreFields

    public var errorDescription: String? {
        switch self {
        case .nonJSON:
            "smartctl 返回的内容不是 JSON。"
        case .missingCoreFields:
            "smartctl JSON 中缺少形成健康结论所需的核心 SMART 字段。"
        }
    }
}

public enum SmartctlParser {
    public static func parse(
        data: Data,
        readMode: ReadMode,
        smartctlPath: String?,
        processExitStatus: Int32?
    ) throws -> SmartSnapshot {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? JSONObject
        else {
            throw SmartctlParserError.nonJSON
        }

        let rawJSON = String(data: data, encoding: .utf8) ?? "{}"
        let smartctl = json.dictionary("smartctl")
        let device = json.dictionary("device")
        let log = json.dictionary("nvme_smart_health_information_log")
        let ataAttributes = parseATAAttributes(from: json)
        let scsiErrorCounters = parseSCSIErrorCounters(from: json)
        let status = json.dictionary("smart_status")
        let localTime = json.dictionary("local_time")
        let exitStatus = smartctl?.int("exit_status").map(Int32.init) ?? processExitStatus
        let protocolFamily = DiskProtocolFamily.infer(
            deviceType: device?.string("type"),
            protocolName: device?.string("protocol"),
            hasNVMeLog: log != nil,
            hasATAAttributes: !ataAttributes.isEmpty,
            hasSCSIErrorCounters: scsiErrorCounters.hasData
        )

        let capturedAt: Date
        if let time = localTime?.int64("time_t") {
            capturedAt = Date(timeIntervalSince1970: TimeInterval(time))
        } else {
            capturedAt = Date()
        }

        let scsiModel = [json.string("scsi_vendor"), json.string("scsi_product")]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let deviceInfo = SmartDeviceInfo(
            deviceName: device?.string("name") ?? "未返回",
            infoName: device?.string("info_name"),
            type: device?.string("type"),
            protocolName: device?.string("protocol") ?? protocolFamily.rawValue,
            modelName: json.string("model_name") ?? (scsiModel.isEmpty ? nil : scsiModel),
            serialNumber: json.string("serial_number"),
            firmwareVersion: json.string("firmware_version"),
            nvmeVersion: json.dictionary("nvme_version")?.string("string"),
            namespaceCount: json.int("nvme_number_of_namespaces"),
            rotationRateRPM: json.int("rotation_rate"),
            ataVersion: json.dictionary("ata_version")?.string("string"),
            sataVersion: json.dictionary("sata_version")?.string("string"),
            scsiVersion: json.string("scsi_version")
        )

        let ataValues = normalizedATAValues(ataAttributes)
        let scsiRead = scsiErrorCounters.read?.totalUncorrected
        let scsiWrite = scsiErrorCounters.write?.totalUncorrected
        let scsiVerify = scsiErrorCounters.verify?.totalUncorrected
        let metrics = SmartHealthMetrics(
            protocolFamily: protocolFamily,
            smartPassed: smartPassed(status?.bool("passed"), exitStatus: exitStatus),
            criticalWarning: log?.int("critical_warning"),
            temperatureCelsius: log?.int("temperature") ?? json.dictionary("temperature")?.int("current") ?? ataValues.temperature,
            availableSparePercent: log?.int("available_spare") ?? json.dictionary("spare_available")?.int("current_percent"),
            availableSpareThresholdPercent: log?.int("available_spare_threshold") ?? json.dictionary("spare_available")?.int("threshold_percent"),
            percentageUsed: log?.int("percentage_used") ?? json.dictionary("endurance_used")?.int("current_percent") ?? ataValues.percentageUsed,
            dataUnitsRead: log?.int64("data_units_read"),
            dataUnitsWritten: log?.int64("data_units_written"),
            hostReads: log?.int64("host_reads"),
            hostWrites: log?.int64("host_writes"),
            controllerBusyTime: log?.int64("controller_busy_time"),
            powerCycles: log?.int64("power_cycles") ?? json.int64("power_cycle_count"),
            powerOnHours: log?.int64("power_on_hours") ?? json.dictionary("power_on_time")?.int64("hours") ?? ataValues.powerOnHours,
            unsafeShutdowns: log?.int64("unsafe_shutdowns"),
            mediaErrors: log?.int64("media_errors"),
            errorLogEntries: log?.int64("num_err_log_entries") ?? json.dictionary("ata_smart_error_log")?.dictionary("summary")?.int64("count"),
            reallocatedSectorCount: ataValues.reallocated,
            reallocationEventCount: ataValues.reallocationEvents,
            currentPendingSectorCount: ataValues.pending,
            offlineUncorrectableSectorCount: ataValues.offlineUncorrectable,
            reportedUncorrectableErrors: ataValues.reportedUncorrectable,
            commandTimeoutCount: ataValues.commandTimeouts,
            crcErrorCount: ataValues.crcErrors,
            endToEndErrorCount: ataValues.endToEndErrors,
            ataAttributeCount: ataAttributes.isEmpty ? nil : ataAttributes.count,
            ataFailingAttributeCount: ataAttributes.isEmpty ? nil : ataAttributes.filter(\.isFailingNow).count,
            ataPastFailureAttributeCount: ataAttributes.isEmpty ? nil : ataAttributes.filter(\.hasFailedInPast).count,
            scsiGrownDefectList: json.int64("scsi_grown_defect_list"),
            scsiNonMediumErrorCount: json.int64("scsi_non_medium_error_count")
                ?? json.dictionary("scsi_error_counter_log")?.dictionary("non_medium_error")?.int64("count"),
            scsiReadUncorrectedErrors: scsiRead,
            scsiWriteUncorrectedErrors: scsiWrite,
            scsiVerifyUncorrectedErrors: scsiVerify,
            scsiErrorCounterAvailable: scsiErrorCounters.hasData ? true : nil
        )

        guard metrics.hasCoreFields else {
            throw SmartctlParserError.missingCoreFields
        }

        let messages = parseMessages(from: smartctl)
        let smartctlVersion = parseVersion(from: smartctl)
        let completeness = HealthEvaluator.readCompleteness(
            metrics: metrics,
            messages: messages,
            exitStatus: exitStatus
        )
        let evaluation = HealthEvaluator.evaluate(
            metrics: metrics,
            readCompleteness: completeness.level,
            smartctlExitStatus: exitStatus
        )

        return SmartSnapshot(
            capturedAt: capturedAt,
            device: deviceInfo,
            metrics: metrics,
            healthLevel: evaluation.level,
            healthReasons: evaluation.reasons,
            readMode: readMode,
            smartctlPath: smartctlPath,
            smartctlVersion: smartctlVersion,
            smartctlExitStatus: exitStatus,
            smartctlMessages: messages,
            rawJSON: rawJSON,
            readCompleteness: completeness.level,
            readCompletenessReasons: completeness.reasons,
            ataAttributes: ataAttributes.isEmpty ? nil : ataAttributes,
            scsiErrorCounters: scsiErrorCounters.hasData ? scsiErrorCounters : nil
        )
    }

    private static func parseATAAttributes(from json: JSONObject) -> [ATASmartAttribute] {
        guard let table = json.dictionary("ata_smart_attributes")?.array("table") else { return [] }
        return table.compactMap { item in
            guard let object = item as? JSONObject,
                  let id = object.int("id") else { return nil }
            let raw = object.dictionary("raw")
            return ATASmartAttribute(
                id: id,
                name: object.string("name") ?? "Attribute \(id)",
                currentValue: object.int("value"),
                worstValue: object.int("worst"),
                threshold: object.int("thresh"),
                whenFailed: object.string("when_failed"),
                rawValue: raw?.int64("value"),
                rawString: raw?.string("string")
            )
        }
    }

    private static func parseSCSIErrorCounters(from json: JSONObject) -> SCSIErrorCounters {
        let log = json.dictionary("scsi_error_counter_log")
        return SCSIErrorCounters(
            read: parseSCSIErrorCounter(log?.dictionary("read")),
            write: parseSCSIErrorCounter(log?.dictionary("write")),
            verify: parseSCSIErrorCounter(log?.dictionary("verify"))
        )
    }

    private static func parseSCSIErrorCounter(_ value: JSONObject?) -> SCSIErrorCounter? {
        guard let value else { return nil }
        let counter = SCSIErrorCounter(
            correctedFast: value.int64("errors_corrected_by_eccfast"),
            correctedDelayed: value.int64("errors_corrected_by_eccdelayed"),
            rereadsOrRewrites: value.int64("errors_corrected_by_rereads_rewrites"),
            totalCorrected: value.int64("total_errors_corrected"),
            correctionAlgorithmInvocations: value.int64("correction_algorithm_invocations"),
            gigabytesProcessed: value.double("gigabytes_processed"),
            totalUncorrected: value.int64("total_uncorrected_errors")
        )
        return counter.hasData ? counter : nil
    }

    private static func normalizedATAValues(_ attributes: [ATASmartAttribute]) -> (
        temperature: Int?,
        percentageUsed: Int?,
        powerOnHours: Int64?,
        reallocated: Int64?,
        reallocationEvents: Int64?,
        pending: Int64?,
        offlineUncorrectable: Int64?,
        reportedUncorrectable: Int64?,
        commandTimeouts: Int64?,
        crcErrors: Int64?,
        endToEndErrors: Int64?
    ) {
        func raw(_ id: Int) -> Int64? {
            attributes.first(where: { $0.id == id })?.rawValue
        }

        let lifetimeAttribute = attributes.first { attribute in
            let name = attribute.name.lowercased()
            return name.contains("percent_lifetime") || name.contains("ssd_life_left") ||
                name.contains("remaining_lifetime") || name.contains("media_wearout") ||
                name.contains("percentage_used")
        }
        let percentageUsed: Int? = lifetimeAttribute.flatMap { attribute in
            let name = attribute.name.lowercased()
            if name.contains("percentage_used") || name.contains("lifetime_used") {
                return boundedPercent(attribute.rawValue.map(Int.init) ?? attribute.currentValue)
            }
            let remaining = boundedPercent(attribute.currentValue ?? attribute.rawValue.map(Int.init))
            return remaining.map { 100 - $0 }
        }

        return (
            temperature: raw(194).map(Int.init) ?? raw(190).map(Int.init),
            percentageUsed: percentageUsed,
            powerOnHours: raw(9),
            reallocated: raw(5),
            reallocationEvents: raw(196),
            pending: raw(197),
            offlineUncorrectable: raw(198),
            reportedUncorrectable: raw(187),
            commandTimeouts: raw(188),
            crcErrors: raw(199),
            endToEndErrors: raw(184)
        )
    }

    private static func boundedPercent(_ value: Int?) -> Int? {
        guard let value, (0...100).contains(value) else { return nil }
        return value
    }

    private static func smartPassed(_ reported: Bool?, exitStatus: Int32?) -> Bool? {
        guard let exitStatus else { return reported }
        let currentHealthFailureMask: Int32 = (1 << 3) | (1 << 4)
        return (exitStatus & currentHealthFailureMask) != 0 ? false : reported
    }

    private static func parseMessages(from smartctl: JSONObject?) -> [SmartctlMessage] {
        guard let rawMessages = smartctl?.array("messages") else { return [] }
        return rawMessages.compactMap { item in
            guard let object = item as? JSONObject else { return nil }
            return SmartctlMessage(
                severity: object.string("severity") ?? "info",
                message: object.string("string") ?? ""
            )
        }
        .filter { !$0.message.isEmpty }
    }

    private static func parseVersion(from smartctl: JSONObject?) -> String? {
        guard let version = smartctl?.array("version") else { return nil }
        let parts = version.compactMap { item -> String? in
            if let int = item as? Int { return String(int) }
            if let string = item as? String { return string }
            return nil
        }
        return parts.isEmpty ? nil : parts.joined(separator: ".")
    }
}
