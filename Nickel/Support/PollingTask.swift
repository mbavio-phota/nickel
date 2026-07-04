import Foundation

/// Runs `body` repeatedly, stopping when `condition` returns `false` or the enclosing task
/// is cancelled. Intended to be driven from a single, stable SwiftUI `.task` modifier so
/// cancellation happens automatically when the view disappears — and only then. Driving
/// this from a `.task(id:)` keyed on state that `body` itself mutates (e.g. a
/// working/idle flag flipped by the very poll it drives) risks SwiftUI tearing the task
/// down mid-iteration, right after the mutation and before the rest of `body` runs.
///
/// `interval` is re-evaluated before every sleep (not just once at call time), so callers
/// can vary the cadence — e.g. faster while an agent is working — without needing to
/// restart the task.
///
/// `body` runs once immediately before the first sleep, so callers get a fresh value right
/// away rather than waiting a full interval.
func poll(
    every interval: @escaping () -> Duration,
    while condition: @escaping () -> Bool,
    _ body: @escaping () async -> Void
) async {
    while !Task.isCancelled && condition() {
        await body()

        if Task.isCancelled || !condition() {
            return
        }

        do {
            try await Task.sleep(for: interval())
        } catch {
            return
        }
    }
}
