import AppKit
import Foundation

enum AppleScriptRunnerError: LocalizedError, Equatable {
    case automationDenied
    case applicationNotRunning
    case hostApplicationInvalidated
    case executionFailed(number: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .automationDenied:
            "Automation access was denied. Allow Notch Capture in System Settings → Privacy & Security → Automation."
        case .applicationNotRunning:
            "The media application is not running."
        case .hostApplicationInvalidated:
            "Notch Capture was rebuilt or removed while it was running. Quit and reopen the app."
        case let .executionFailed(_, message):
            message
        }
    }
}

enum AppleScriptResult: Sendable, Equatable {
    case none
    case string(String)
    case data(Data)
}

protocol AppleScriptRunning: Sendable {
    var hostExecutableIsCurrent: Bool { get }
    func run(_ source: String) async throws -> AppleScriptResult
}

extension AppleScriptRunning {
    var hostExecutableIsCurrent: Bool { true }
}

final class AppleScriptRunner: AppleScriptRunning, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.lipe.notchcapture.applescript")
    private let hostExecutableURL: URL?
    private let initialHostExecutableIdentity: ExecutableFileIdentity?
    private var scripts: [String: NSAppleScript] = [:]

    init(hostExecutableURL: URL? = Bundle.main.executableURL) {
        self.hostExecutableURL = hostExecutableURL
        initialHostExecutableIdentity = ExecutableFileIdentity.read(from: hostExecutableURL)
    }

    var hostExecutableIsCurrent: Bool {
        guard initialHostExecutableIdentity != nil else { return true }
        return ExecutableFileIdentity.read(from: hostExecutableURL) == initialHostExecutableIdentity
    }

    func run(_ source: String) async throws -> AppleScriptResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard hostExecutableIsCurrent else {
                    continuation.resume(throwing: AppleScriptRunnerError.hostApplicationInvalidated)
                    return
                }
                var errorInfo: NSDictionary?
                let script: NSAppleScript
                if let cached = scripts[source] {
                    script = cached
                } else {
                    guard let compiled = NSAppleScript(source: source) else {
                        continuation.resume(throwing: AppleScriptRunnerError.executionFailed(number: 0, message: "Unable to create AppleScript."))
                        return
                    }
                    scripts[source] = compiled
                    script = compiled
                }

                let descriptor = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let number = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
                    let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "AppleScript failed."
                    continuation.resume(throwing: Self.classifyExecutionError(
                        number: number,
                        message: message,
                        hostExecutableIsCurrent: hostExecutableIsCurrent
                    ))
                    return
                }

                switch descriptor.descriptorType {
                case typeNull:
                    continuation.resume(returning: .none)
                case typeData:
                    continuation.resume(returning: .data(descriptor.data))
                default:
                    if let value = descriptor.stringValue {
                        continuation.resume(returning: .string(value))
                    } else if !descriptor.data.isEmpty {
                        continuation.resume(returning: .data(descriptor.data))
                    } else {
                        continuation.resume(returning: .none)
                    }
                }
            }
        }
    }

    nonisolated static func classifyExecutionError(
        number: Int,
        message: String,
        hostExecutableIsCurrent: Bool
    ) -> AppleScriptRunnerError {
        switch number {
        case -1743:
            hostExecutableIsCurrent ? .automationDenied : .hostApplicationInvalidated
        case -600, -609:
            .applicationNotRunning
        default:
            .executionFailed(number: number, message: message)
        }
    }
}

private struct ExecutableFileIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64

    static func read(from url: URL?) -> Self? {
        guard let url else { return nil }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else { return nil }
        return Self(device: device.uint64Value, inode: inode.uint64Value)
    }
}
