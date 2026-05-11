import Foundation

public struct Entry: Codable, Equatable, Hashable, Identifiable {
    public let task: String
    public let start: Date
    public let stop: Date
    public var id: String { "\(task)|\(start.timeIntervalSince1970)|\(stop.timeIntervalSince1970)" }

    public init(task: String, start: Date, stop: Date) {
        self.task = task
        self.start = start
        self.stop = stop
    }

    public var duration: TimeInterval { stop.timeIntervalSince(start) }
}

public struct DayLog: Equatable, Codable {
    public let date: String
    public var entries: [Entry]

    public init(date: String, entries: [Entry]) {
        self.date = date
        self.entries = entries
    }

    public var totalSeconds: TimeInterval {
        entries.reduce(0) { $0 + $1.duration }
    }

    /// Human-readable total in the form "8h 00m". Written to the JSON file
    /// for at-a-glance viewing; recomputed on read (any value present in the
    /// file is ignored).
    public var totalFormatted: String {
        let s = max(0, Int(totalSeconds.rounded()))
        let h = s / 3600
        let m = (s % 3600) / 60
        return String(format: "%dh %02dm", h, m)
    }

    private enum CodingKeys: String, CodingKey {
        case date, total, entries
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        try c.encode(totalFormatted, forKey: .total)
        try c.encode(entries, forKey: .entries)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        entries = try c.decode([Entry].self, forKey: .entries)
        // Any "total" value present in the file is ignored — recomputed from entries.
    }
}

public struct CurrentSession: Codable, Equatable {
    public let task: String
    public let startedAt: Date

    public init(task: String, startedAt: Date) {
        self.task = task
        self.startedAt = startedAt
    }
}

private let timesheetISOFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private extension JSONEncoder.DateEncodingStrategy {
    static var iso8601WithFractionalAndOffset: JSONEncoder.DateEncodingStrategy {
        .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(timesheetISOFormatter.string(from: date))
        }
    }
}

private extension JSONDecoder.DateDecodingStrategy {
    static var iso8601WithFractionalAndOffset: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let d = timesheetISOFormatter.date(from: str) { return d }
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            if let d = fallback.date(from: str) { return d }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date: \(str)")
        }
    }
}

public extension JSONEncoder {
    static let timesheet: JSONEncoder = {
        let e = JSONEncoder()
        // `.sortedKeys` for deterministic output. `total` sorts after `entries`
        // alphabetically so it appears near the bottom of each file.
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601WithFractionalAndOffset
        return e
    }()
}

public extension JSONDecoder {
    static let timesheet: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601WithFractionalAndOffset
        return d
    }()
}
