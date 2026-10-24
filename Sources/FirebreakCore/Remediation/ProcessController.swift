import Foundation
import Darwin

public final class ProcessController: Sendable {
    public init() {}
    
    @discardableResult
    public func freeze(swarm: ProcessSwarm) -> [Int32: Bool] {
        dispatchSignal(SIGSTOP, to: swarm)
    }
    
    @discardableResult
    public func thaw(swarm: ProcessSwarm) -> [Int32: Bool] {
        dispatchSignal(SIGCONT, to: swarm)
    }
    
    @discardableResult
    public func terminate(swarm: ProcessSwarm, force: Bool = false) -> [Int32: Bool] {
        dispatchSignal(force ? SIGKILL : SIGTERM, to: swarm)
    }
    
    private func dispatchSignal(_ signal: Int32, to swarm: ProcessSwarm) -> [Int32: Bool] {
        var results: [Int32: Bool] = [:]
        for proc in swarm.processes {
            // Guard against sending signals to init / launchd
            guard proc.pid > 1 else { continue }
            let ret = kill(proc.pid, signal)
            results[proc.pid] = (ret == 0)
        }
        return results
    }
}
