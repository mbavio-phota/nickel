import Foundation

/// Runs `body` repeatedly on `interval`, stopping when `condition` returns `false` or the
/// enclosing task is cancelled. Intended to be driven from a SwiftUI `.task` modifier so
/// cancellation happens automatically when the view disappears.
///
/// `body` runs once immediately before the first sleep, so callers get a fresh value right
/// away rather than waiting a full interval.
func poll(
    every interval: Duration,
    while condition: @escaping () -> Bool,
    _ body: @escaping () async -> Void
) async {
    while !Task.isCancelled && condition() {
        await body()

        if Task.isCancelled || !condition() {
            return
        }

        do {
            try await Task.sleep(for: interval)
        } catch {
            return
        }
    }
}
