import Foundation
import ServiceManagement

@MainActor
final class PrivilegedHelperManager: ObservableObject {
    static let plistName = "com.shixinqvq.shixinlab.diskhealth.helper.plist"

    var service: SMAppService {
        SMAppService.daemon(plistName: Self.plistName)
    }

    var statusText: String {
        switch service.status {
        case .notRegistered:
            "未注册"
        case .enabled:
            "已启用"
        case .requiresApproval:
            "需要在系统设置中批准"
        case .notFound:
            "当前构建未启用"
        @unknown default:
            "未知状态"
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }
}
