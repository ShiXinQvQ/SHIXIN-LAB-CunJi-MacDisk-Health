import Foundation

public enum AppRuntimeConfiguration {
    public static let publishedAppSupportDirectoryName = "SHIXIN LAB MacDisk Health"
    public static let internalV2AppSupportDirectoryName = "SHIXIN LAB MacDisk Health v2"

    public static var appSupportDirectoryName: String {
        bundleString(forKey: "SHIXINAppSupportDirectoryName") ?? internalV2AppSupportDirectoryName
    }

    public static var speedTestCacheDirectoryName: String {
        bundleString(forKey: "SHIXINSpeedTestCacheDirectoryName") ?? appSupportDirectoryName
    }

    public static var isInternalV2: Bool {
        appSupportDirectoryName == internalV2AppSupportDirectoryName
    }

    public static var isPublishedRelease: Bool {
        appSupportDirectoryName == publishedAppSupportDirectoryName
    }

    public static var previousVersionAppSupportDirectoryName: String? {
        previousVersionAppSupportDirectoryName(for: appSupportDirectoryName)
    }

    public static func previousVersionAppSupportDirectoryName(for directoryName: String) -> String? {
        if directoryName == internalV2AppSupportDirectoryName {
            return publishedAppSupportDirectoryName
        }
        if directoryName == publishedAppSupportDirectoryName {
            return internalV2AppSupportDirectoryName
        }
        return nil
    }

    private static func bundleString(forKey key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
