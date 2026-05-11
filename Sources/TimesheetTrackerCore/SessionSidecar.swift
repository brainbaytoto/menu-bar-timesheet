import Foundation

public final class SessionSidecar {
    public let rootDirectory: URL
    private let fm: FileManager

    public init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fm = fileManager
    }

    private var url: URL { rootDirectory.appendingPathComponent("current-session.json") }

    public func read() throws -> CurrentSession? {
        guard fm.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.timesheet.decode(CurrentSession.self, from: data)
    }

    public func write(_ session: CurrentSession) throws {
        if !fm.fileExists(atPath: rootDirectory.path) {
            try fm.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        }
        let data = try JSONEncoder.timesheet.encode(session)
        try data.write(to: url, options: .atomic)
    }

    public func clear() throws {
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }
}
