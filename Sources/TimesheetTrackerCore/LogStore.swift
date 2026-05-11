import Foundation

public final class LogStore {
    public let rootDirectory: URL
    private let fm: FileManager

    public init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fm = fileManager
    }

    private var logsDirectory: URL { rootDirectory.appendingPathComponent("logs") }

    private func fileURL(forDay day: String) -> URL {
        logsDirectory.appendingPathComponent("\(day).json")
    }

    private func ensureLogsDirectory() throws {
        if !fm.fileExists(atPath: logsDirectory.path) {
            try fm.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        }
    }

    public func readDay(_ day: String) throws -> DayLog {
        let url = fileURL(forDay: day)
        guard fm.fileExists(atPath: url.path) else {
            return DayLog(date: day, entries: [])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.timesheet.decode(DayLog.self, from: data)
    }

    public func append(_ entry: Entry, toDay day: String) throws {
        try ensureLogsDirectory()
        var dayLog = try readDay(day)
        dayLog.entries.append(entry)
        try writeDay(dayLog)
    }

    /// Overwrite a day's file with the given DayLog (sorted by start time).
    public func writeDay(_ dayLog: DayLog) throws {
        try ensureLogsDirectory()
        let sorted = DayLog(date: dayLog.date,
                            entries: dayLog.entries.sorted { $0.start < $1.start })
        let data = try JSONEncoder.timesheet.encode(sorted)
        try data.write(to: fileURL(forDay: sorted.date), options: .atomic)
    }
}
