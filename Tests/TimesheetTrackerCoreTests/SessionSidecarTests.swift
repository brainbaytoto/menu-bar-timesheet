import XCTest
@testable import TimesheetTrackerCore

final class SessionSidecarTests: XCTestCase {
    var tempDir: URL!
    var sidecar: SessionSidecar!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ts-sidecar-\(UUID().uuidString)")
        sidecar = SessionSidecar(rootDirectory: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_readReturnsNilWhenAbsent() throws {
        XCTAssertNil(try sidecar.read())
    }

    func test_writeThenReadRoundTrips() throws {
        let session = CurrentSession(task: "Hello", startedAt: Date(timeIntervalSince1970: 1_715_400_000))
        try sidecar.write(session)
        XCTAssertEqual(try sidecar.read(), session)
    }

    func test_clearRemovesSidecar() throws {
        try sidecar.write(CurrentSession(task: "X", startedAt: Date()))
        try sidecar.clear()
        XCTAssertNil(try sidecar.read())
    }

    func test_clearWhenAbsentIsNoOp() throws {
        XCTAssertNoThrow(try sidecar.clear())
    }
}
