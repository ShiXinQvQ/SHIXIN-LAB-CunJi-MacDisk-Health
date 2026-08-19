import Foundation
import ShixinDiskHealthCore

@objc protocol DiskHealthPrivilegedHelperProtocol {
    func readDisk0SMART(reply: @escaping (Data?, Int32, String?) -> Void)
}

final class DiskHealthPrivilegedHelper: NSObject, DiskHealthPrivilegedHelperProtocol, NSXPCListenerDelegate {
    private let listener = NSXPCListener(machServiceName: "com.shixinqvq.shixinlab.diskhealth.helper")

    override init() {
        super.init()
        listener.delegate = self
    }

    func run() {
        listener.resume()
        RunLoop.current.run()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // The Helper is a dormant development skeleton and is intentionally
        // fail-closed. A future signed release must add and review caller
        // authentication before this service can accept any connection.
        connection.invalidate()
        return false
    }

    func readDisk0SMART(reply: @escaping (Data?, Int32, String?) -> Void) {
        let smartctlURL = bundledSmartctlURL()
        let replyBox = XPCReplyBox(reply)
        Task {
            do {
                let output = try await SmartctlRunner.runValidatedProcess(
                    executableURL: smartctlURL,
                    arguments: SmartctlRunner.allowedArguments,
                    environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
                )
                replyBox.call(output.stdout, output.exitStatus, String(data: output.stderr, encoding: .utf8))
            } catch {
                replyBox.call(nil, -1, error.localizedDescription)
            }
        }
    }

    private func bundledSmartctlURL() -> URL {
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let candidates = [
            executableURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/Tools/smartctl"),
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/Tools/smartctl")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
            ?? URL(fileURLWithPath: "/nonexistent/smartctl")
    }
}

private final class XPCReplyBox: @unchecked Sendable {
    private let reply: (Data?, Int32, String?) -> Void

    init(_ reply: @escaping (Data?, Int32, String?) -> Void) {
        self.reply = reply
    }

    func call(_ data: Data?, _ status: Int32, _ error: String?) {
        reply(data, status, error)
    }
}

DiskHealthPrivilegedHelper().run()
