import Foundation
import Synchronization

/// Intercepts every request of `URLSession.shared`, records its body and answers
/// with a canned status + body (an SSE stream for successful responses).
final class MockURLProtocol: URLProtocol {
    struct Stub: Sendable {
        let status: Int
        let body: String
    }

    private struct State {
        var stub: Stub?
        var lastBody: Data?
    }

    private static let state = Mutex(State())

    static func stub(status: Int = 200, body: String) {
        state.withLock {
            $0.stub = Stub(status: status, body: body)
            $0.lastBody = nil
        }
    }

    /// SSE body: one `data:` line per payload.
    static func stubStream(_ payloads: [String]) {
        stub(body: payloads.map { "data: \($0)\n\n" }.joined())
    }

    static var lastRequestJSON: [String: Any]? {
        guard let data = state.withLock({ $0.lastBody }) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.readAll)
        let stub = Self.state.withLock { state in
            state.lastBody = body
            return state.stub
        }
        guard let stub, let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "text/event-stream"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readAll(_ stream: InputStream) -> Data {
        var data = Data()
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
