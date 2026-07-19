import AppKit
import Foundation

enum AppleScriptRunnerError: LocalizedError, Equatable {
    case automationDenied
    case applicationNotRunning
    case executionFailed(number: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .automationDenied:
            "Automation access was denied. Allow Notch Capture in System Settings → Privacy & Security → Automation."
        case .applicationNotRunning:
            "The media application is not running."
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

final class AppleScriptRunner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.lipe.notchcapture.applescript")
    private var scripts: [String: NSAppleScript] = [:]

    func run(_ source: String) async throws -> AppleScriptResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
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
                    switch number {
                    case -1743: continuation.resume(throwing: AppleScriptRunnerError.automationDenied)
                    case -600, -609: continuation.resume(throwing: AppleScriptRunnerError.applicationNotRunning)
                    default: continuation.resume(throwing: AppleScriptRunnerError.executionFailed(number: number, message: message))
                    }
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
}
