import Foundation

public enum SmartctlCommandKind: Codable, Hashable, Sendable {
    case core
    case extended

    public var baseArguments: [String] {
        switch self {
        case .core:
            ["-i", "-H", "-A", "--json"]
        case .extended:
            ["-a", "--json"]
        }
    }

    public var diagnosticTitle: String {
        switch self {
        case .core: "核心健康读取"
        case .extended: "扩展完整读取"
        }
    }
}

public struct SmartctlCommandRequest: Codable, Hashable, Sendable {
    public var profile: SmartctlAccessProfile
    public var deviceType: SmartctlDeviceType
    public var kind: SmartctlCommandKind

    public init(
        profile: SmartctlAccessProfile,
        deviceType: SmartctlDeviceType = .auto,
        kind: SmartctlCommandKind
    ) {
        self.profile = profile
        self.deviceType = deviceType
        self.kind = kind
    }

    public var arguments: [String] {
        deviceType.argumentPrefix + kind.baseArguments + [profile.devicePath]
    }
}

public actor SmartctlRunner {
    public static let allowedDevice = "/dev/disk0"
    public static let coreArguments = ["-i", "-H", "-A", "--json", SmartctlRunner.allowedDevice]
    public static let extendedArguments = ["-a", "--json", SmartctlRunner.allowedDevice]
    public static let allowedArguments = extendedArguments
    public static let defaultEnvironment = [
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
    ]

    private let resourceRoots: [URL]
    private let inventoryProvider: @Sendable () -> DiskInventory

    public init(
        resourceRoots: [URL] = [],
        inventoryProvider: @escaping @Sendable () -> DiskInventory = { DiskInventoryReader.read() }
    ) {
        self.resourceRoots = resourceRoots
        self.inventoryProvider = inventoryProvider
    }

    public func readDisk0(manualPath: String? = nil) async -> SmartctlReadOutcome {
        await read(target: Self.defaultDisk0Target(), manualPath: manualPath)
    }

    public func read(target requestedTarget: DiskTarget, manualPath: String? = nil) async -> SmartctlReadOutcome {
        let currentInventory = inventoryProvider()
        guard let target = Self.resolveEnumeratedTarget(requestedTarget, in: currentInventory) else {
            return .failure(
                SmartctlFailure(
                    title: "所选硬盘未通过实时枚举校验",
                    message: "检测前重新读取磁盘列表时，目标节点、设备身份或允许的读取类型已不再匹配。",
                    recovery: "本次不会执行 smartctl，也不会自动改读其他硬盘。请刷新磁盘列表并重新选择目标。"
                )
            )
        }
        guard let profile = target.smartctlAccessProfile, target.canReadSMART else {
            return .failure(
                SmartctlFailure(
                    title: "此目标不支持 SMART 读取",
                    message: "\(target.displayName) 当前不是可读取 SMART 的本地 whole-disk 设备。",
                    recovery: "请选择本机内置或本地外置硬盘。网络卷只能进行普通文件速度测试，不能读取 SMART。"
                )
            )
        }

        guard FileManager.default.fileExists(atPath: profile.devicePath) else {
            return .failure(
                SmartctlFailure(
                    title: "\(profile.devicePath) 不存在",
                    message: "未发现所选硬盘设备节点 \(profile.devicePath)。",
                    recovery: "请刷新磁盘列表，确认外置硬盘仍已连接并且 macOS 已识别。"
                )
            )
        }

        let locator = SmartctlLocator(resourceRoots: resourceRoots, manualPath: manualPath)
        guard let location = locator.locate() else {
            return .failure(
                SmartctlFailure(
                    title: "smartctl 路径找不到",
                    message: "未找到可执行的 smartctl。",
                    recovery: "可以安装 smartmontools：brew install smartmontools，或在设置中手动选择 smartctl 路径。本 App 不会自动安装任何组件。",
                    checkedPaths: locator.checkedPathDescriptions()
                )
            )
        }

        var attempts: [SmartctlAttemptFailure] = []
        for deviceType in profile.allowedDeviceTypes {
            let coreRequest = SmartctlCommandRequest(profile: profile, deviceType: deviceType, kind: .core)
            let coreOutput: ProcessOutput
            do {
                try Self.validate(executableURL: location.executableURL, request: coreRequest)
                coreOutput = try await runProcess(executableURL: location.executableURL, request: coreRequest)
            } catch {
                if error is CancellationError {
                    return .failure(cancelledFailure())
                }
                if error is ProcessExecutionError {
                    return .failure(
                        SmartctlFailure(
                            title: "SMART 读取超时或输出异常",
                            message: error.localizedDescription,
                            recovery: "已终止本次只读查询。请确认硬盘与桥接器响应正常后再试。"
                        )
                    )
                }
                attempts.append(SmartctlAttemptFailure(deviceType: deviceType, output: nil, error: error))
                continue
            }

            var coreSnapshot: SmartSnapshot
            do {
                guard let parsed = try parseProcessOutput(coreOutput, location: location) else {
                    attempts.append(SmartctlAttemptFailure(deviceType: deviceType, output: coreOutput, error: nil))
                    continue
                }
                coreSnapshot = parsed
                try Self.validateReportedDevicePath(
                    coreSnapshot.device.deviceName,
                    expectedDevicePath: profile.devicePath
                )
                coreSnapshot.applyDiskTarget(target)
            } catch {
                attempts.append(SmartctlAttemptFailure(deviceType: deviceType, output: coreOutput, error: error))
                continue
            }

            let extendedRequest = SmartctlCommandRequest(profile: profile, deviceType: deviceType, kind: .extended)
            do {
                try Self.validate(executableURL: location.executableURL, request: extendedRequest)
                let extendedOutput = try await runProcess(executableURL: location.executableURL, request: extendedRequest)
                var extendedSnapshot = try? parseProcessOutput(extendedOutput, location: location)
                if var candidate = extendedSnapshot {
                    do {
                        try Self.validateReportedDevicePath(
                            candidate.device.deviceName,
                            expectedDevicePath: profile.devicePath
                        )
                        candidate.applyDiskTarget(target)
                        extendedSnapshot = candidate
                    } catch {
                        extendedSnapshot = nil
                    }
                }
                let combined = combine(
                    coreSnapshot: coreSnapshot,
                    coreRequest: coreRequest,
                    coreOutput: coreOutput,
                    extendedSnapshot: extendedSnapshot,
                    extendedRequest: extendedRequest,
                    extendedOutput: extendedOutput,
                    location: location
                )
                return .success(combined)
            } catch {
                if error is CancellationError {
                    return .failure(cancelledFailure())
                }
                let diagnosticOutput = ProcessOutput(
                    stdout: Data(),
                    stderr: Data(error.localizedDescription.utf8),
                    exitStatus: -1
                )
                return .success(
                    combine(
                        coreSnapshot: coreSnapshot,
                        coreRequest: coreRequest,
                        coreOutput: coreOutput,
                        extendedSnapshot: nil,
                        extendedRequest: extendedRequest,
                        extendedOutput: diagnosticOutput,
                        location: location
                    )
                )
            }
        }

        return .failure(
            SmartctlFailure(
                title: "SMART 读取不可用",
                message: "所选设备或外置桥接器没有返回可用的核心 SMART 健康数据。",
                recovery: "这不等同于硬盘故障。部分 USB / Thunderbolt 硬盘盒不会透传 SMART；可以换用支持 SMART 透传的硬盘盒后再试。",
                checkedPaths: locator.checkedPathDescriptions(),
                rawOutputPreview: attempts.map(\.preview).filter { !$0.isEmpty }.joined(separator: "\n\n").prefixString(2_000)
            )
        )
    }

    public static func validate(executableURL: URL, request: SmartctlCommandRequest) throws {
        guard executableURL.lastPathComponent == "smartctl" else {
            throw ValidationError.invalidExecutable
        }
        guard request.profile.allowedDeviceTypes.contains(request.deviceType) else {
            throw ValidationError.invalidDeviceType
        }
        guard isWholeDiskDevicePath(request.profile.devicePath) else {
            throw ValidationError.invalidDevicePath
        }
        guard request.arguments == SmartctlCommandRequest(
            profile: request.profile,
            deviceType: request.deviceType,
            kind: request.kind
        ).arguments else {
            throw ValidationError.invalidArguments
        }
    }

    public static func resolveEnumeratedTarget(
        _ requestedTarget: DiskTarget,
        in inventory: DiskInventory
    ) -> DiskTarget? {
        guard let enumeratedTarget = inventory.smartTarget(matching: requestedTarget),
              enumeratedTarget.canReadSMART,
              let profile = enumeratedTarget.smartctlAccessProfile,
              isWholeDiskDevicePath(profile.devicePath) else {
            return nil
        }
        return enumeratedTarget
    }

    public static func validateReportedDevicePath(
        _ reportedDevicePath: String,
        expectedDevicePath: String
    ) throws {
        guard reportedDevicePath == "未返回" || reportedDevicePath == expectedDevicePath else {
            throw SmartctlResultValidationError.unexpectedDevicePath(
                expected: expectedDevicePath,
                reported: reportedDevicePath
            )
        }
    }

    public static func mergeExitStatuses(_ statuses: Int32?...) -> Int32? {
        let validStatuses = statuses.compactMap { $0 }.filter { $0 >= 0 }
        guard !validStatuses.isEmpty else { return nil }
        return validStatuses.reduce(0) { $0 | $1 }
    }

    public static func validate(executableURL: URL, arguments: [String]) throws {
        guard executableURL.lastPathComponent == "smartctl" else {
            throw ValidationError.invalidExecutable
        }
        guard arguments == coreArguments || arguments == extendedArguments else {
            throw ValidationError.invalidArguments
        }
    }

    private static func runValidatedProcess(
        executableURL: URL,
        request: SmartctlCommandRequest,
        environment: [String: String] = SmartctlRunner.defaultEnvironment
    ) async throws -> ProcessOutput {
        try validate(executableURL: executableURL, request: request)
        return try await runProcessUnchecked(
            executableURL: executableURL,
            arguments: request.arguments,
            environment: environment
        )
    }

    public static func runValidatedProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = SmartctlRunner.defaultEnvironment
    ) async throws -> ProcessOutput {
        try validate(executableURL: executableURL, arguments: arguments)
        return try await runProcessUnchecked(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment
        )
    }

    public static func defaultDisk0Target() -> DiskTarget {
        let identity = DiskIdentityKey(rawValue: "device:/dev/disk0", source: "default-disk0")
        return DiskTarget(
            id: identity.rawValue,
            displayName: "默认内置 SSD",
            detailName: "/dev/disk0",
            connectionKind: .internalPhysical,
            smartSupportStatus: .supported,
            smartctlAccessProfile: SmartctlAccessProfile(devicePath: allowedDevice, allowedDeviceTypes: [.auto]),
            identityKey: identity,
            isLocalVolume: true,
            isInternal: true,
            protocolName: nil
        )
    }

    private static func isWholeDiskDevicePath(_ path: String) -> Bool {
        guard path.hasPrefix("/dev/disk") else { return false }
        guard !path.hasPrefix("/dev/rdisk") else { return false }
        let name = URL(fileURLWithPath: path).lastPathComponent
        guard name.range(of: #"^disk\d+$"#, options: .regularExpression) != nil else {
            return false
        }
        return true
    }

    private static func runProcessUnchecked(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]
    ) async throws -> ProcessOutput {
        try await ProcessExecutor.run(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            timeoutSeconds: 20
        )
    }

    private func runProcess(executableURL: URL, request: SmartctlCommandRequest) async throws -> ProcessOutput {
        try await Self.runValidatedProcess(executableURL: executableURL, request: request)
    }

    private func parseProcessOutput(_ output: ProcessOutput, location: SmartctlLocation) throws -> SmartSnapshot? {
        guard !output.stdout.isEmpty else { return nil }
        do {
            return try SmartctlParser.parse(
                data: output.stdout,
                readMode: location.mode,
                smartctlPath: location.executableURL.path,
                processExitStatus: output.exitStatus
            )
        } catch SmartctlParserError.missingCoreFields {
            throw SmartctlParserError.missingCoreFields
        } catch SmartctlParserError.nonJSON {
            throw SmartctlParserError.nonJSON
        } catch {
            throw error
        }
    }

    private func combine(
        coreSnapshot: SmartSnapshot,
        coreRequest: SmartctlCommandRequest,
        coreOutput: ProcessOutput,
        extendedSnapshot: SmartSnapshot?,
        extendedRequest: SmartctlCommandRequest,
        extendedOutput: ProcessOutput,
        location: SmartctlLocation
    ) -> SmartSnapshot {
        var combined = coreSnapshot
        let extendedMessages = extendedSnapshot?.smartctlMessages ?? []
        let combinedMessages = coreSnapshot.smartctlMessages + extendedMessages
        let extendedCompleteness = HealthEvaluator.readCompleteness(
            metrics: coreSnapshot.metrics,
            messages: combinedMessages,
            exitStatus: extendedOutput.exitStatus
        )
        let finalCompleteness: ReadCompleteness
        let finalCompletenessReasons: [String]
        if extendedOutput.exitStatus == 0, extendedSnapshot != nil {
            finalCompleteness = .complete
            finalCompletenessReasons = ["核心健康数据和扩展信息均已读取。"]
        } else if extendedSnapshot == nil {
            finalCompleteness = .coreCompleteSupplementalUnavailable
            finalCompletenessReasons = ["核心健康数据已读取成功；扩展输出无法完整验证，不等同于硬盘故障。"]
        } else if extendedCompleteness.level == .coreCompleteSupplementalUnavailable {
            finalCompleteness = .coreCompleteSupplementalUnavailable
            finalCompletenessReasons = extendedCompleteness.reasons
        } else {
            finalCompleteness = coreSnapshot.displayReadCompleteness
            finalCompletenessReasons = coreSnapshot.displayReadCompletenessReasons
        }

        let finalExitStatus = Self.mergeExitStatuses(
            coreSnapshot.smartctlExitStatus,
            coreOutput.exitStatus,
            extendedSnapshot?.smartctlExitStatus,
            extendedOutput.exitStatus
        )
        let health = HealthEvaluator.evaluate(
            metrics: coreSnapshot.metrics,
            readCompleteness: finalCompleteness,
            smartctlExitStatus: finalExitStatus
        )
        combined.healthLevel = health.level
        combined.healthReasons = health.reasons
        combined.readCompleteness = finalCompleteness
        combined.readCompletenessReasons = finalCompletenessReasons
        combined.smartctlExitStatus = finalExitStatus
        combined.smartctlMessages = combinedMessages
        combined.rawJSON = extendedSnapshot?.rawJSON ?? coreSnapshot.rawJSON
        combined.coreRawJSON = coreSnapshot.rawJSON
        combined.extendedRawJSON = extendedSnapshot?.rawJSON
        combined.smartctlDiagnostics = [
            diagnostic(
                title: coreRequest.kind.diagnosticTitle,
                request: coreRequest,
                output: coreOutput,
                messages: coreSnapshot.smartctlMessages
            ),
            diagnostic(
                title: extendedRequest.kind.diagnosticTitle,
                request: extendedRequest,
                output: extendedOutput,
                messages: extendedMessages
            )
        ]
        combined.smartctlPath = location.executableURL.path
        combined.readMode = location.mode
        return combined
    }

    private func diagnostic(
        title: String,
        request: SmartctlCommandRequest,
        output: ProcessOutput,
        messages: [SmartctlMessage]
    ) -> SmartctlDiagnostic {
        SmartctlDiagnostic(
            title: title,
            arguments: ["smartctl"] + request.arguments,
            exitStatus: output.exitStatus,
            messages: messages,
            stderrText: String(data: output.stderr, encoding: .utf8)
        )
    }

    private func cancelledFailure() -> SmartctlFailure {
        SmartctlFailure(
            title: "SMART 检测已取消",
            message: "所选硬盘的只读检测任务已停止。",
            recovery: "确认硬盘仍已连接后可以重新检测。"
        )
    }
}

public enum ValidationError: Error, LocalizedError, Sendable {
    case invalidExecutable
    case invalidArguments
    case invalidDevicePath
    case invalidDeviceType

    public var errorDescription: String? {
        switch self {
        case .invalidExecutable:
            "只允许执行名为 smartctl 的工具。"
        case .invalidArguments:
            "只允许执行固定只读参数矩阵：Auto 不传 -d，或仅使用 -d nvme|sat|scsi|sntasmedia|sntjmicron|sntrealtek，再执行固定的核心或扩展读取请求。"
        case .invalidDevicePath:
            "命令只允许 whole-disk /dev/diskN 设备节点，不允许分区、rdisk 或任意路径；实际读取前还必须通过实时磁盘枚举校验。"
        case .invalidDeviceType:
            "只允许使用该设备枚举结果允许的 smartctl 设备类型。"
        }
    }
}

public enum SmartctlResultValidationError: Error, LocalizedError, Sendable {
    case unexpectedDevicePath(expected: String, reported: String)

    public var errorDescription: String? {
        switch self {
        case .unexpectedDevicePath(let expected, let reported):
            "smartctl 返回的设备为 \(reported)，与所选目标 \(expected) 不一致，已拒绝使用该结果。"
        }
    }
}

private struct SmartctlAttemptFailure: Sendable {
    var deviceType: SmartctlDeviceType
    var output: ProcessOutput?
    var error: Error?

    var preview: String {
        var parts = ["设备类型：\(deviceType.title)"]
        if let output {
            parts.append("Exit \(output.exitStatus)")
            if !output.preview.isEmpty {
                parts.append(SmartPrivacyRedactor.redactJSON(output.preview))
            }
        }
        if let error {
            parts.append(error.localizedDescription)
        }
        return parts.joined(separator: "\n")
    }
}

private extension StringProtocol {
    func prefixString(_ maxLength: Int) -> String {
        String(prefix(maxLength))
    }
}
