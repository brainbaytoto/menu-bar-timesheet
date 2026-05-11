import Foundation

public protocol Clock: AnyObject {
    func now() -> Date
}

public final class SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}

public final class FakeClock: Clock {
    public var currentTime: Date
    public init(_ start: Date = Date(timeIntervalSince1970: 0)) { self.currentTime = start }
    public func now() -> Date { currentTime }
    public func advance(by interval: TimeInterval) { currentTime = currentTime.addingTimeInterval(interval) }
}
