import DiskArbitration
import Foundation

public enum DiskInventoryReader {
    public static func read() -> DiskInventory {
        let diskDescriptions = readDiskDescriptions()
        let mountedVolumes = readMountedVolumes()
        var targets = buildDiskTargets(from: diskDescriptions, mountedVolumes: mountedVolumes)
        targets.append(contentsOf: buildUnmatchedVolumeTargets(mountedVolumes, existingTargets: targets))
        targets = targets.sorted { lhs, rhs in
            sortKey(lhs) < sortKey(rhs)
        }
        return DiskInventory(targets: targets)
    }

    public static func acceptsPhysicalWholeDiskMetadata(
        isWholeDisk: Bool,
        mediaName: String?,
        mediaContent: String?,
        mediaPath: String?,
        protocolName: String?,
        modelName: String?
    ) -> Bool {
        guard isWholeDisk else { return false }
        let lowerProtocol = (protocolName ?? "").lowercased()
        let lowerModel = (modelName ?? "").lowercased()
        let lowerMediaName = (mediaName ?? "").lowercased()
        let lowerMediaPath = (mediaPath ?? "").lowercased()
        let lowerContent = (mediaContent ?? "").lowercased()

        guard !lowerProtocol.contains("virtual"), !lowerModel.contains("disk image") else {
            return false
        }
        guard lowerMediaName != "appleapfsmedia",
              !lowerMediaPath.contains("appleapfscontainerscheme"),
              lowerContent != "ef57347c-0000-11aa-aa11-00306543ecac" else {
            return false
        }
        return true
    }

    private static func readDiskDescriptions() -> [DiskDescription] {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return [] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return names
            .filter { $0.hasPrefix("disk") }
            .sorted()
            .compactMap { name in
                let path = "/dev/\(name)"
                return path.withCString { pointer -> DiskDescription? in
                    guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, pointer),
                          let rawDescription = DADiskCopyDescription(disk) else {
                        return nil
                    }
                    let description = rawDescription as NSDictionary
                    return DiskDescription(bsdName: name, devicePath: path, description: description)
                }
            }
    }

    private static func readMountedVolumes() -> [MountedVolume] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsLocalKey,
            .volumeIsInternalKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isLocal = values?.volumeIsLocal ?? url.isFileURL
            return MountedVolume(
                url: url.standardizedFileURL,
                name: values?.volumeName ?? url.lastPathComponent,
                isLocal: isLocal,
                isInternal: values?.volumeIsInternal,
                capacityBytes: values?.volumeTotalCapacity.map(Int64.init),
                availableBytes: values?.volumeAvailableCapacityForImportantUsage
            )
        }
    }

    private static func buildDiskTargets(
        from descriptions: [DiskDescription],
        mountedVolumes: [MountedVolume]
    ) -> [DiskTarget] {
        let wholeDisks = descriptions.filter(\.isPhysicalWholeDisk)

        return wholeDisks.map { disk in
            let relatedDescriptions = descriptions.filter { candidate in
                if let servicePath = disk.deviceServicePath {
                    return candidate.deviceServicePath == servicePath
                }
                return candidate.wholeDiskBSDName == disk.bsdName
            }
            let mounted = preferredMountedVolume(
                for: disk,
                relatedDescriptions: relatedDescriptions,
                mountedVolumes: mountedVolumes
            )
            let volumeURL = mounted?.url
            let volumeName = mounted?.name
            let isInternal = disk.isInternal
            let isExternal = isInternal == false || disk.isRemovable == true || disk.isEjectable == true
            let connectionKind: DiskConnectionKind = isInternal == true ? .internalPhysical : (isExternal ? .externalPhysical : .unknown)
            let protocolName = disk.protocolName
            let devicePath = disk.devicePath
            let displayName = bestDisplayName(disk: disk, volumeName: volumeName)
            let identity = identityKey(
                for: disk,
                relatedDescriptions: relatedDescriptions,
                volumeName: volumeName
            )
            let allowedTypes = allowedSmartctlDeviceTypes(
                protocolName: protocolName,
                modelName: disk.modelName,
                connectionKind: connectionKind
            )
            let supportStatus: SmartSupportStatus
            if isLikelyVirtualDisk(disk) {
                supportStatus = .unsupportedVirtualDisk
            } else {
                supportStatus = .supported
            }

            return DiskTarget(
                id: "runtime-disk:\(devicePath)",
                displayName: displayName,
                detailName: detailName(for: disk, volumeURL: volumeURL),
                connectionKind: connectionKind,
                smartSupportStatus: supportStatus,
                smartctlAccessProfile: SmartctlAccessProfile(devicePath: devicePath, allowedDeviceTypes: allowedTypes),
                identityKey: identity,
                volumeURL: volumeURL,
                volumeName: volumeName,
                isLocalVolume: true,
                isInternal: isInternal,
                protocolName: protocolName,
                modelName: disk.modelName,
                mediaSizeBytes: disk.mediaSizeBytes,
                volumeCapacityBytes: mounted?.capacityBytes,
                volumeAvailableBytes: mounted?.availableBytes
            )
        }
    }

    private static func preferredMountedVolume(
        for disk: DiskDescription,
        relatedDescriptions: [DiskDescription],
        mountedVolumes: [MountedVolume]
    ) -> MountedVolume? {
        let relatedPaths = Set(relatedDescriptions.compactMap { $0.volumeURL?.standardizedFileURL.path })
        return mountedVolumes
            .filter { relatedPaths.contains($0.url.standardizedFileURL.path) }
            .sorted { volumePreference($0, isInternal: disk.isInternal) < volumePreference($1, isInternal: disk.isInternal) }
            .first
    }

    private static func volumePreference(_ volume: MountedVolume, isInternal: Bool?) -> String {
        let path = volume.url.standardizedFileURL.path
        if isInternal == true, path == "/" {
            return "0-\(path)"
        }
        if isInternal != true, path.hasPrefix("/Volumes/") {
            return "0-\(path)"
        }
        if path.hasPrefix("/System/Volumes/") {
            return "2-\(path)"
        }
        return "1-\(path)"
    }

    private static func buildUnmatchedVolumeTargets(
        _ mountedVolumes: [MountedVolume],
        existingTargets: [DiskTarget]
    ) -> [DiskTarget] {
        let knownVolumePaths = Set(existingTargets.compactMap { $0.volumeURL?.standardizedFileURL.path })
        return mountedVolumes
            .filter { !knownVolumePaths.contains($0.url.path) }
            .map { volume in
                let kind: DiskConnectionKind = volume.isLocal
                    ? ((volume.isInternal == true) ? .internalPhysical : .externalPhysical)
                    : .networkVolume
                let status: SmartSupportStatus = volume.isLocal ? .unsupportedNoWholeDisk : .unsupportedNetworkVolume
                let identity = DiskIdentityKey(
                    rawValue: "volume:\(volume.url.path)",
                    source: volume.isLocal ? "mounted-local-volume" : "mounted-network-volume"
                )
                return DiskTarget(
                    id: "runtime-volume:\(volume.url.standardizedFileURL.path)",
                    displayName: volume.name.isEmpty ? volume.url.lastPathComponent : volume.name,
                    detailName: volume.url.path,
                    connectionKind: kind,
                    smartSupportStatus: status,
                    smartctlAccessProfile: nil,
                    identityKey: identity,
                    volumeURL: volume.url,
                    volumeName: volume.name,
                    isLocalVolume: volume.isLocal,
                    isInternal: volume.isInternal,
                    volumeCapacityBytes: volume.capacityBytes,
                    volumeAvailableBytes: volume.availableBytes
                )
            }
    }

    public static func allowedSmartctlDeviceTypes(
        protocolName: String?,
        modelName: String?,
        connectionKind: DiskConnectionKind
    ) -> [SmartctlDeviceType] {
        let lowerProtocol = (protocolName ?? "").lowercased()
        let lowerModel = (modelName ?? "").lowercased()
        var types: [SmartctlDeviceType] = []

        if connectionKind == .externalPhysical, lowerProtocol.contains("usb") {
            if lowerModel.contains("realtek") || lowerModel.contains("rtl92") {
                types.append(.sntRealtek)
            }
            if lowerModel.contains("asmedia") || lowerModel.contains("asm23") {
                types.append(.sntASMedia)
            }
            if lowerModel.contains("jmicron") || lowerModel.contains("jms58") {
                types.append(.sntJMicron)
            }
        }

        types.append(.auto)
        if lowerProtocol.contains("nvme") {
            types.append(.nvme)
        }
        if lowerProtocol.contains("usb") || lowerProtocol.contains("sata") || lowerProtocol.contains("sat") || connectionKind == .externalPhysical {
            types.append(contentsOf: [.sat, .scsi, .nvme])
        }
        var seen: Set<SmartctlDeviceType> = []
        return types.filter { seen.insert($0).inserted }
    }

    private static func bestDisplayName(disk: DiskDescription, volumeName: String?) -> String {
        if let volumeName, !volumeName.isEmpty {
            return volumeName
        }
        if let model = disk.modelName, !model.isEmpty {
            return model
        }
        if let media = disk.mediaName, !media.isEmpty {
            return media
        }
        return disk.devicePath
    }

    private static func detailName(for disk: DiskDescription, volumeURL: URL?) -> String {
        var parts = [disk.devicePath]
        if let protocolName = disk.protocolName, !protocolName.isEmpty {
            parts.append(protocolName)
        }
        if let volumeURL {
            parts.append(volumeURL.path)
        }
        return parts.joined(separator: " · ")
    }

    private static func identityKey(
        for disk: DiskDescription,
        relatedDescriptions: [DiskDescription],
        volumeName: String?
    ) -> DiskIdentityKey {
        if let uuid = disk.mediaUUID, !uuid.isEmpty {
            return DiskIdentityKey(rawValue: "media:\(uuid)", source: "disk-arbitration-media-uuid")
        }
        if let relatedUUID = relatedDescriptions.compactMap(\.mediaUUID).sorted().first {
            return DiskIdentityKey(rawValue: "media:\(relatedUUID)", source: "disk-arbitration-related-media-uuid")
        }
        if let model = disk.modelName, let size = disk.mediaSizeBytes {
            let transport = disk.protocolName ?? "unknown"
            return DiskIdentityKey(
                rawValue: "model-size-protocol-device:\(model):\(size):\(transport):\(disk.devicePath)",
                source: "model-size-protocol-device"
            )
        }
        if let volumeName, !volumeName.isEmpty {
            return DiskIdentityKey(rawValue: "device-volume:\(disk.devicePath):\(volumeName)", source: "device-volume")
        }
        return DiskIdentityKey(rawValue: "device:\(disk.devicePath)", source: "device-path")
    }

    private static func isLikelyVirtualDisk(_ disk: DiskDescription) -> Bool {
        let haystack = [
            disk.protocolName,
            disk.modelName,
            disk.mediaName
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
        return haystack.contains("disk image") || haystack.contains("synthesized") || haystack.contains("virtual")
    }

    private static func sortKey(_ target: DiskTarget) -> String {
        let group: String
        switch target.connectionKind {
        case .internalPhysical: group = "0"
        case .externalPhysical: group = "1"
        case .networkVolume: group = "2"
        case .unknown: group = "3"
        }
        return "\(group)-\(target.devicePath ?? target.displayName)"
    }
}

private struct DiskDescription {
    var bsdName: String
    var devicePath: String
    var description: NSDictionary

    var isWholeDisk: Bool {
        bool(kDADiskDescriptionMediaWholeKey) ?? (wholeDiskBSDName == bsdName)
    }

    var isPhysicalWholeDisk: Bool {
        DiskInventoryReader.acceptsPhysicalWholeDiskMetadata(
            isWholeDisk: isWholeDisk,
            mediaName: mediaName,
            mediaContent: mediaContent,
            mediaPath: mediaPath,
            protocolName: protocolName,
            modelName: modelName
        )
    }

    var wholeDiskBSDName: String {
        if let range = bsdName.range(of: #"s\d+.*$"#, options: .regularExpression) {
            return String(bsdName[..<range.lowerBound])
        }
        return bsdName
    }

    var mediaName: String? {
        string(kDADiskDescriptionMediaNameKey)
    }

    var modelName: String? {
        string(kDADiskDescriptionDeviceModelKey)
    }

    var protocolName: String? {
        string(kDADiskDescriptionDeviceProtocolKey)
    }

    var mediaContent: String? {
        string(kDADiskDescriptionMediaContentKey)
    }

    var mediaPath: String? {
        string(kDADiskDescriptionMediaPathKey)
    }

    var deviceServicePath: String? {
        string(kDADiskDescriptionDevicePathKey)
    }

    var volumeName: String? {
        string(kDADiskDescriptionVolumeNameKey)
    }

    var volumeURL: URL? {
        description[kDADiskDescriptionVolumePathKey] as? URL
    }

    var mediaUUID: String? {
        guard let value = description[kDADiskDescriptionMediaUUIDKey] else { return nil }
        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        let cfValue = value as CFTypeRef
        guard CFGetTypeID(cfValue) == CFUUIDGetTypeID() else { return nil }
        // String interpolation of CFUUID includes a process-specific pointer.
        let uuid = unsafeDowncast(cfValue, to: CFUUID.self)
        guard let uuidString = CFUUIDCreateString(kCFAllocatorDefault, uuid) else { return nil }
        return (uuidString as String).uppercased()
    }

    var mediaSizeBytes: Int64? {
        number(kDADiskDescriptionMediaSizeKey)?.int64Value
    }

    var volumeCapacityBytes: Int64? {
        nil
    }

    var volumeAvailableBytes: Int64? {
        nil
    }

    var isInternal: Bool? {
        bool(kDADiskDescriptionDeviceInternalKey)
    }

    var isRemovable: Bool? {
        bool(kDADiskDescriptionMediaRemovableKey)
    }

    var isEjectable: Bool? {
        bool(kDADiskDescriptionMediaEjectableKey)
    }

    private func string(_ key: CFString) -> String? {
        description[key] as? String
    }

    private func number(_ key: CFString) -> NSNumber? {
        description[key] as? NSNumber
    }

    private func bool(_ key: CFString) -> Bool? {
        if let value = description[key] as? Bool {
            return value
        }
        return (description[key] as? NSNumber)?.boolValue
    }
}

private struct MountedVolume {
    var url: URL
    var name: String
    var isLocal: Bool
    var isInternal: Bool?
    var capacityBytes: Int64?
    var availableBytes: Int64?
}
