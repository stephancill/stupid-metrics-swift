import Foundation
@testable import StupidMetrics
import Testing

private enum SampleError: Error {
    case notConfigured
    case serviceError(String)
}

private enum DescribedError: Error, CustomStringConvertible {
    case failed
    var description: String {
        "secret user text"
    }
}

private struct PlainError: Error {
    let detail = "secret"
}

struct ErrorDescriptionTests {
    @Test func dropsPayloadsAndText() {
        #expect(ErrorDescription.describe(SampleError.notConfigured) == "SampleError.notConfigured")
        #expect(ErrorDescription.describe(SampleError.serviceError("Hi @alice")) == "SampleError.serviceError")
        #expect(ErrorDescription.describe(DescribedError.failed) == "DescribedError.0")
        #expect(ErrorDescription.describe(PlainError()) == "PlainError")
        #expect(ErrorDescription.describe(URLError(.notConnectedToInternet)) == "URLError.-1009")
        #expect(ErrorDescription.describe(NSError(domain: "Example", code: 3, userInfo: [NSLocalizedDescriptionKey: "secret"])) == "Example.3")
        #expect(ErrorDescription.describe(CancellationError()) == "CancellationError")
    }
}

struct LimitsTests {
    @Test func sanitizesProps() {
        var props = ["Bad Key": "x", "network": String(repeating: "a", count: 100)]
        for index in 0 ..< 10 {
            props["k\(index)"] = "v"
        }
        let sanitized = Limits.sanitize(props)
        #expect(sanitized.count == Limits.maxProps)
        #expect(sanitized["Bad Key"] == nil)
        #expect(Limits.isValidToken("source_error", maxLength: 64))
        #expect(!Limits.isValidToken("Refresh", maxLength: 64))
        #expect(!Limits.isValidToken("", maxLength: 64))
    }
}

/// Records requests and answers with a scripted status.
final class FakeServer: @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    var status = 200

    var requests: [URLRequest] {
        lock.withLock { _requests }
    }

    var transport: Transport {
        { request in
            let status = self.lock.withLock {
                self._requests.append(request)
                return self.status
            }
            if status == 0 { throw URLError(.notConnectedToInternet) }
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
}

struct EngineTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "StupidMetricsTests-\(UUID().uuidString)")
    let suite = "StupidMetricsTests-\(UUID().uuidString)"
    var defaults: UserDefaults {
        UserDefaults(suiteName: suite)!
    }

    let server = FakeServer()

    func makeEngine(version: String = "1.0") -> Engine {
        Engine(
            configuration: .init(appKey: "smk_test", endpoint: URL(string: "https://metrics.example")!),
            directory: directory,
            defaults: defaults,
            transport: server.transport,
            makeContext: { installId in
                MetricContext(appVersion: version, build: "1", environment: "", platform: "ios", osVersion: "26.1", deviceModel: "iPhone17,1", installId: installId)
            },
            resolveEnvironment: { "testflight" }
        )
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
    }

    @Test func sendsBatchesWithContextAndAuth() async throws {
        let engine = makeEngine()
        await engine.startSession()
        await engine.enqueue(.event, name: "refresh", props: ["network": "x"], value: 812, message: nil, at: Date())
        await engine.flush()

        let request = try #require(server.requests.first)
        #expect(request.url?.absoluteString == "https://metrics.example/v1/events")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer smk_test")
        let json = try body(request)
        let context = try #require(json["context"] as? [String: Any])
        #expect(context["environment"] as? String == "testflight")
        let events = try #require(json["events"] as? [[String: Any]])
        #expect(events.map { $0["name"] as? String } == ["session_start", "refresh"])
        #expect(await engine.queuedEventCount == 0)
    }

    @Test func dropsInvalidNames() async {
        let engine = makeEngine()
        await engine.enqueue(.event, name: "Has Spaces", props: [:], value: nil, message: nil, at: Date())
        #expect(await engine.queuedEventCount == 0)
    }

    @Test func keepsEventsWhenOfflineAndRestoresThemAfterRelaunch() async {
        server.status = 0
        let engine = makeEngine()
        await engine.enqueue(.error, name: "source_error", props: ["network": "x"], value: nil, message: "URLError.-1009", at: Date())
        await engine.flush()
        #expect(await engine.queuedEventCount == 1)

        server.status = 200
        let relaunched = makeEngine()
        #expect(await relaunched.queuedEventCount == 1)
        await relaunched.flush()
        #expect(await relaunched.queuedEventCount == 0)
    }

    @Test func dropsBatchesTheServerRejects() async {
        server.status = 400
        let engine = makeEngine()
        await engine.enqueue(.event, name: "refresh", props: [:], value: nil, message: nil, at: Date())
        await engine.flush()
        #expect(await engine.queuedEventCount == 0)
    }

    @Test func queuedEventsKeepTheVersionThatRecordedThem() async throws {
        server.status = 0
        let old = makeEngine(version: "1.0")
        await old.enqueue(.event, name: "refresh", props: [:], value: nil, message: nil, at: Date())
        await old.flush()

        server.status = 200
        let updated = makeEngine(version: "1.1")
        await updated.enqueue(.event, name: "refresh", props: [:], value: nil, message: nil, at: Date())
        await updated.flush()
        let versions = try server.requests.suffix(2).map { try body($0)["context"] as? [String: Any] }.map { $0?["appVersion"] as? String }
        #expect(versions == ["1.0", "1.1"])
    }

    @Test func eventsBeforeTheFirstSessionStartShareItsSession() async {
        let engine = makeEngine()
        await engine.enqueue(.event, name: "accounts", props: [:], value: 1, message: nil, at: Date())
        await engine.startSession(renew: false)
        await engine.flush()
        let events = server.requests.first.flatMap { try? body($0)["events"] as? [[String: Any]] } ?? []
        #expect(Set(events.compactMap { $0["sessionId"] as? String }).count == 1)
    }

    @Test func startsANewSessionAfterTheTimeout() async {
        let engine = makeEngine()
        await engine.startSession()
        let first = await engine.sessionId
        let now = Date()
        await engine.didEnterBackground(at: now)
        await engine.willEnterForeground(at: now.addingTimeInterval(60))
        #expect(await engine.sessionId == first)
        await engine.didEnterBackground(at: now)
        await engine.willEnterForeground(at: now.addingTimeInterval(31 * 60))
        #expect(await engine.sessionId != first)
    }

    @Test func uploadsDiagnosticsWithContext() async throws {
        let engine = makeEngine()
        await engine.enqueueDiagnostic(kind: "metric", json: Data(#"{"applicationExitMetrics":{}}"#.utf8))
        await engine.flush()
        let request = try #require(server.requests.first { $0.url?.path() == "/v1/diagnostics" })
        let json = try body(request)
        #expect(json["kind"] as? String == "metric")
        #expect((json["payload"] as? [String: Any])?["applicationExitMetrics"] != nil)
        #expect((json["context"] as? [String: Any])?["installId"] as? String != nil)

        server.status = 200
        let before = server.requests.count
        await engine.flush()
        #expect(server.requests.count == before)
    }

    @Test func resetForgetsTheInstall() async {
        server.status = 0
        let engine = makeEngine()
        await engine.enqueue(.event, name: "refresh", props: [:], value: nil, message: nil, at: Date())
        let installId = defaults.string(forKey: Engine.installIdKey)
        await engine.reset(makeContext: { MetricContext(appVersion: "1.0", build: "1", environment: "", platform: "ios", osVersion: "26.1", deviceModel: "x", installId: $0) })
        #expect(await engine.queuedEventCount == 0)
        #expect(defaults.string(forKey: Engine.installIdKey) != installId)
    }
}
