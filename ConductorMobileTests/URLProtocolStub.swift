import Foundation

/// Intercepts all requests made through a `URLSession` configured with this protocol,
/// letting tests assert on the outgoing `URLRequest` and control the response.
final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    /// Set by the test before making a request; captures method/path/query/headers/body
    /// once the request comes through, and supplies the canned response.
    struct Stub {
        let statusCode: Int
        let responseBody: Data
        let onRequest: (@Sendable (URLRequest) -> Void)?

        init(statusCode: Int, responseBody: Data, onRequest: (@Sendable (URLRequest) -> Void)? = nil) {
            self.statusCode = statusCode
            self.responseBody = responseBody
            self.onRequest = onRequest
        }
    }

    /// Protected by being set/read only from the test's serial expectations; XCTest runs
    /// each test method sequentially so a static var is sufficient here.
    nonisolated(unsafe) static var stub: Stub?

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let stub = URLProtocolStub.stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        // Capture the body from httpBodyStream if needed (URLSession sometimes moves
        // httpBody into a stream for stubbed sessions).
        var requestForInspection = request
        if requestForInspection.httpBody == nil, let stream = request.httpBodyStream {
            requestForInspection.httpBody = Self.readStream(stream)
        }
        stub.onRequest?(requestForInspection)

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readStream(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return data
    }
}
