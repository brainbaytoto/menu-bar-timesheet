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

public struct DayLog: Codable, Equatable {
    public let date: String
    public var entries: [Entry]

    public init(date: String, entries: [Entry]) {
        self.date = date
        self.entries = entries
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
