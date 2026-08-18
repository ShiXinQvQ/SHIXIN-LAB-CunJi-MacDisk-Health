import Foundation

public struct SmartctlLocator: Sendable {
    public var resourceRoots: [URL]
    public var manualPath: String?

    public init(resourceRoots: [URL] = [], manualPath: String? = nil) {
        self.resourceRoots = resourceRoots
        self.manualPath = manualPath
    }

    public func checkedPathDescriptions() -> [String] {
        candidateURLs().map { $0.executableURL.path }
    }

    public func locate() -> SmartctlLocation? {
        candidateURLs().first { location in
            FileManager.default.isExecutableFile(atPath: location.executableURL.path)
        }
    }

    public func candidateURLs() -> [SmartctlLocation] {
        var candidates: [SmartctlLocation] = []

        var roots = resourceRoots
        if let mainResourceURL = Bundle.main.resourceURL {
            roots.append(mainResourceURL)
        }

        for root in roots {
            candidates.append(
                SmartctlLocation(
                    executableURL: root.appendingPathComponent("Tools/smartctl"),
                    mode: .bundled,
                    label: "App 内置 smartctl"
                )
            )
            candidates.append(
                SmartctlLocation(
                    executableURL: root.appendingPathComponent("Resources/Tools/smartctl"),
                    mode: .bundled,
                    label: "App 内置 smartctl"
                )
            )
        }

        candidates.append(
            SmartctlLocation(
                executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/smartctl"),
                mode: .homebrewAppleSilicon,
                label: "Apple Silicon Homebrew"
            )
        )
        candidates.append(
            SmartctlLocation(
                executableURL: URL(fileURLWithPath: "/usr/local/bin/smartctl"),
                mode: .homebrewIntel,
                label: "Intel Homebrew"
            )
        )

        if let pathSmartctl = findInPATH() {
            candidates.append(
                SmartctlLocation(
                    executableURL: pathSmartctl,
                    mode: .path,
                    label: "PATH"
                )
            )
        }

        if let manualPath, !manualPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates.append(
                SmartctlLocation(
                    executableURL: URL(fileURLWithPath: manualPath),
                    mode: .manual,
                    label: "手动选择"
                )
            )
        }

        var seen = Set<String>()
        return candidates.filter { location in
            let path = location.executableURL.standardizedFileURL.path
            if seen.contains(path) { return false }
            seen.insert(path)
            return true
        }
    }

    private func findInPATH() -> URL? {
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for component in pathValue.split(separator: ":") {
            let url = URL(fileURLWithPath: String(component)).appendingPathComponent("smartctl")
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}
