import Foundation
import Darwin

public struct SignalOutcome: Sendable {
    public let delivered: Int
    public let failed: Int
    public let skipped: Int

    public var summary: String {
        var parts = ["\(delivered) signaled"]
        if failed > 0 { parts.append("\(failed) denied") }
        if skipped > 0 { parts.append("\(skipped) protected") }
        return parts.joined(separator: ", ")
    }
}

public final class ProcessController: Sendable {
    /// Session-critical processes that must never be stopped or killed. Freezing any of these
    /// (ControlCenter / SystemUIServer host the menu bar) locks up the whole UI, including Firebreak.
    public static let protectedNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow", "Dock", "Finder",
        "ControlCenter", "SystemUIServer", "NotificationCenter", "coreaudiod",
        "Spotlight", "talagent", "UserEventAgent", "Firebreak", "FirebreakApp"
    ]

    public init() {}

    public static func isProtected(_ proc: ProcessNode) -> Bool {
        proc.pid <= 1 || proc.pid == getpid() || protectedNames.contains(proc.name)
    }

    @discardableResult
    public func freeze(swarm: ProcessSwarm) -> SignalOutcome {
        dispatchSignal(SIGSTOP, to: swarm)
    }

    /// Resumes only the stopped members when the snapshot knows which they are, so unrelated
    /// suspended jobs (e.g. a Ctrl-Z'd shell job in the same group) are left alone.
    @discardableResult
    public func thaw(swarm: ProcessSwarm) -> SignalOutcome {
        guard swarm.isFrozen else { return dispatchSignal(SIGCONT, to: swarm) }
        let stopped = ProcessSwarm(
            groupKey: swarm.groupKey,
            displayName: swarm.displayName,
            category: swarm.category,
            processes: swarm.processes.filter(\.isStopped)
        )
        return dispatchSignal(SIGCONT, to: stopped)
    }
    
    /// Sends SIGCONT to explicit PIDs (used to resume everything Firebreak froze on quit).
    @discardableResult
    public func resume(pids: Set<Int32>) -> Int {
        pids.filter { $0 > 1 && kill($0, SIGCONT) == 0 }.count
    }

    @discardableResult
    public func terminate(swarm: ProcessSwarm, force: Bool = false) -> SignalOutcome {
        guard force else { return dispatchSignal(SIGTERM, to: swarm) }
        // Stop the whole swarm first so supervisors can't respawn children mid-kill.
        dispatchSignal(SIGSTOP, to: swarm)
        return dispatchSignal(SIGKILL, to: swarm)
    }

    @discardableResult
    private func dispatchSignal(_ signal: Int32, to swarm: ProcessSwarm) -> SignalOutcome {
        var delivered = 0, failed = 0, skipped = 0
        for proc in swarm.processes {
            guard !Self.isProtected(proc) else {
                skipped += 1
                continue
            }
            if kill(proc.pid, signal) == 0 {
                delivered += 1
            } else {
                failed += 1
            }
        }
        return SignalOutcome(delivered: delivered, failed: failed, skipped: skipped)
    }
}
