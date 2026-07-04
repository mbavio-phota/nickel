import Foundation

/// Generic loading-state wrapper for view models that fetch data asynchronously.
enum Loadable<T> {
    case idle
    case loading
    case loaded(T)
    case failed(ConductorError)

    var value: T? {
        if case .loaded(let value) = self {
            return value
        }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    var error: ConductorError? {
        if case .failed(let error) = self {
            return error
        }
        return nil
    }
}
