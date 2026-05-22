import XCTest
@testable import LogFoxCore

final class PreStartBufferTests: XCTestCase {

    private func buffer(_ runtime: LogFoxRuntime, _ message: String, level: LogLevel = .info) {
        runtime.buffer(date: Date(), level: level, category: .general, rawMessage: message,
                       rawMetadata: [:], file: "F.swift", line: 1, function: "f()", thread: "main")
    }

    func testTargetIsBufferBeforeStart() {
        let runtime = LogFoxRuntime()
        guard case .buffer = runtime.target(for: .info) else {
            return XCTFail("start öncesi hedef .buffer olmalı")
        }
    }

    func testPreStartLogsFlushedOnStart() {
        let runtime = LogFoxRuntime()
        buffer(runtime, "early-1")
        buffer(runtime, "early-2")

        runtime.start(with: LogFoxConfiguration(persistsToDisk: false, mirrorsToOSLog: false))

        guard case .store(let store) = runtime.target(for: .info) else {
            return XCTFail("start sonrası hedef .store olmalı")
        }
        XCTAssertEqual(store.snapshot().map(\.message), ["early-1", "early-2"])
    }

    func testFlushRespectsMinimumLevel() {
        let runtime = LogFoxRuntime()
        buffer(runtime, "low", level: .debug)
        buffer(runtime, "high", level: .error)

        runtime.start(with: LogFoxConfiguration(minimumLevel: .warning, persistsToDisk: false, mirrorsToOSLog: false))

        guard case .store(let store) = runtime.target(for: .error) else {
            return XCTFail()
        }
        XCTAssertEqual(store.snapshot().map(\.message), ["high"])
    }

    func testBufferAfterStartGoesDirectlyToStore() {
        let runtime = LogFoxRuntime()
        runtime.start(with: LogFoxConfiguration(persistsToDisk: false, mirrorsToOSLog: false))
        buffer(runtime, "after-start")
        guard case .store(let store) = runtime.target(for: .info) else { return XCTFail() }
        XCTAssertEqual(store.snapshot().map(\.message), ["after-start"])
    }
}
