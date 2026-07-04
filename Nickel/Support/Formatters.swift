import Foundation

/// Formatting helpers for the timestamp strings the Conductor API returns. The live API
/// emits Postgres-style timestamps ("2026-07-04 14:27:40.002976+00"); ISO-8601 is also
/// accepted for robustness (the schema just says "string").
enum Formatters {
    private static let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Postgres-style variants, most specific first. `X` matches bare "+00" offsets.
    private static let postgresFormatters: [DateFormatter] = [
        "yyyy-MM-dd HH:mm:ss.SSSSSSX",
        "yyyy-MM-dd HH:mm:ss.SSSX",
        "yyyy-MM-dd HH:mm:ssX",
    ].map { pattern in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter
    }

    /// Parses an API timestamp, or `nil` for unparseable strings rather than crashing.
    static func date(from string: String) -> Date? {
        if let date = isoWithFraction.date(from: string) ?? isoPlain.date(from: string) {
            return date
        }
        for formatter in postgresFormatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }

    /// Renders an API timestamp as a short relative string ("2m ago"), or the raw string
    /// unchanged if it can't be parsed.
    static func relative(from string: String) -> String {
        guard let date = date(from: string) else {
            return string
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
