import Foundation

/// Decoded shape of any 4xx/5xx error body the Conductor API returns.
struct StructuredError: Codable, Equatable {
    let code: String?
    let userMessage: String
    let debugMessage: String?
    let retryable: Bool?
    let source: String?
    let stack: String?
    let underlying: [StructuredError]?

    // `details` is intentionally omitted from decoding: its values are a heterogeneous
    // string/number/bool/null map that isn't needed for display and isn't worth a bespoke
    // decodable wrapper for a diagnostics-only field.
}

/// Normalized error type surfaced to view models — wraps both API-reported errors
/// (`StructuredError`) and local transport/decoding failures behind one interface.
enum ConductorError: Error, Equatable {
    case unauthorized(userMessage: String)
    case server(statusCode: Int, structured: StructuredError)
    case transport(message: String)
    case decoding(message: String)

    /// User-facing message, suitable for display in a `ContentUnavailableView` or alert.
    var userMessage: String {
        switch self {
        case .unauthorized(let userMessage):
            return userMessage
        case .server(_, let structured):
            return structured.userMessage
        case .transport(let message):
            return message
        case .decoding(let message):
            return message
        }
    }

    /// Whether a Retry action makes sense for this error.
    var retryable: Bool {
        switch self {
        case .unauthorized:
            return false
        case .server(_, let structured):
            return structured.retryable ?? false
        case .transport:
            return true
        case .decoding:
            return false
        }
    }

    var statusCode: Int? {
        switch self {
        case .server(let statusCode, _):
            return statusCode
        case .unauthorized:
            return 401
        case .transport, .decoding:
            return nil
        }
    }

    /// Builds the appropriate case from an HTTP response body, special-casing 401.
    static func fromResponse(statusCode: Int, data: Data) -> ConductorError {
        let decoder = JSONDecoder()
        guard let structured = try? decoder.decode(StructuredError.self, from: data) else {
            let message = String(data: data, encoding: .utf8) ?? "Request failed (\(statusCode))."
            return statusCode == 401 ? .unauthorized(userMessage: message) : .server(
                statusCode: statusCode,
                structured: StructuredError(
                    code: nil,
                    userMessage: message,
                    debugMessage: nil,
                    retryable: nil,
                    source: nil,
                    stack: nil,
                    underlying: nil
                )
            )
        }

        if statusCode == 401 {
            return .unauthorized(userMessage: structured.userMessage)
        }
        return .server(statusCode: statusCode, structured: structured)
    }
}
