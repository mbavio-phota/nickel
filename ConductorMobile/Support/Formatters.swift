import Foundation

/// Formatting helpers for the ISO-8601 date strings the Conductor API returns.
enum Formatters {
    /// Parses an ISO-8601 timestamp, trying with-fractional-seconds first and falling back
    /// to whole seconds. Returns `nil` for unparseable strings rather than crashing.
    static func date(from isoString: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: isoString) {
            return date
        }

        let withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]
        return withoutFraction.date(from: isoString)
    }

    /// Renders an ISO-8601 timestamp as a short relative string ("2m ago"), or the raw
    /// string unchanged if it can't be parsed.
    static func relative(from isoString: String) -> String {
        guard let date = date(from: isoString) else {
            return isoString
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
