import Foundation

public final class DomainRecipes: Sendable {
    public init() {}
    
    @discardableResult
    public func shutdownAllSimulators() -> (exitCode: Int32, output: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        task.arguments = ["simctl", "shutdown", "all"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8) ?? ""
            return (task.terminationStatus, out)
        } catch {
            return (-1, "Failed to execute simctl: \(error.localizedDescription)")
        }
    }
}
