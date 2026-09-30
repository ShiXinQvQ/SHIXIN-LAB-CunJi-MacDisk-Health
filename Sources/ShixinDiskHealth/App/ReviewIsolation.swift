import Darwin
import Foundation
import ShixinDiskHealthCore

enum ReviewIsolation {
    /// Runs before constructing stores or applying language preferences, including after Sparkle relaunch.
    static func validateBeforeInitializingStores() {
        #if SHIXIN_UPDATE_TESTING
        let info = Bundle.main.infoDictionary ?? [:]
        guard let home = info["CunJiReviewHome"] as? String,
              home.hasPrefix("/"), home != "/",
              Bundle.main.bundleIdentifier == "com.shixinqvq.shixinlab.diskhealth.review.updater",
              info["SHIXINAppSupportDirectoryName"] as? String == "SHIXIN LAB MacDisk Health review",
              info["SHIXINSpeedTestCacheDirectoryName"] as? String == "SHIXIN LAB MacDisk Health review",
              ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] == home,
              NSHomeDirectory() == home,
              URL(fileURLWithPath: home).resolvingSymlinksInPath().path == home,
              let account = getpwuid(getuid()), String(cString: account.pointee.pw_dir) != home else {
            fatalError("Updater test build requires its isolated review home")
        }
        let receipt = [
            "build": info["CFBundleVersion"] as? String ?? "unknown",
            "home": NSHomeDirectory(), "bundle": Bundle.main.bundlePath,
            "namespace": AppRuntimeConfiguration.appSupportDirectoryName
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
            try data.write(to: URL(fileURLWithPath: home).appendingPathComponent("launch-\(receipt["build"]!).json"), options: .atomic)
        } catch { fatalError("Cannot record isolated review launch: \(error)") }
        #else
        precondition(Bundle.main.object(forInfoDictionaryKey: "CunJiReviewHome") == nil,
                     "Release executable cannot run with review configuration")
        #endif
    }
}
