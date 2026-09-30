import AppKit
import Combine

/// Leases cover the real lifetime of disk tasks, including cancellation and cleanup.
@MainActor
final class UpdateActivityGate: ObservableObject {
    static let shared = UpdateActivityGate()

    @Published private(set) var updateInProgress = false
    @Published private(set) var activityCount = 0
    private(set) var isTerminating = false
    private var activities: Set<UUID> = []
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    var canBeginUpdate: Bool { !updateInProgress && !isTerminating && activities.isEmpty }

    func beginActivity() -> UUID? {
        guard !updateInProgress && !isTerminating else { return nil }
        let token = UUID()
        activities.insert(token)
        activityCount = activities.count
        return token
    }

    func endActivity(_ token: UUID) {
        guard activities.remove(token) != nil else { return }
        activityCount = activities.count
        if activities.isEmpty {
            let waiters = idleWaiters
            idleWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
    }

    func beginUpdate() -> Bool {
        guard canBeginUpdate else { return false }
        updateInProgress = true
        return true
    }

    func endUpdate() { updateInProgress = false }

    func beginTermination() { isTerminating = true }
    func cancelTermination() { isTerminating = false }

    func waitUntilIdle() async {
        guard !activities.isEmpty else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    func beginUserActivity() -> UUID? {
        if let token = beginActivity() { return token }
        guard !isTerminating else { return nil }
        let alert = NSAlert()
        alert.messageText = L10n.t("更新进行中")
        alert.informativeText = L10n.t("请先完成或取消软件更新，再开始检测、测速、保存或导出。")
        alert.addButton(withTitle: L10n.t("好"))
        alert.runModal()
        return nil
    }
}
