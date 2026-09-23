import Foundation

/// What the user is told when an operation fails.
///
/// `error.localizedDescription` used to be concatenated into the toast, which surfaces Firestore internals,
/// cannot be localized, and reads as noise to a vendor. Failures are classified into these cases instead; the
/// underlying error is logged, never shown.
enum AppError {
    /// No usable connection, or the write could not reach the server.
    case offline
    /// The signed-in user is not allowed to touch this record — in practice a security-rules rejection.
    case notAllowed
    /// Anything we have not classified.
    case unexpected

    /// Firestore reports its status as an `NSError` in `FIRFirestoreErrorDomain`; the codes are the gRPC
    /// status values documented at firebase.google.com/docs/reference/swift/firebasefirestore/api/reference/Enums/FirestoreErrorCode
    init(_ error: Error) {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            self = .offline
            return
        }
        switch ns.code {
        case 14, 4: self = .offline           // unavailable, deadline exceeded
        case 7, 16: self = .notAllowed        // permission denied, unauthenticated
        default: self = .unexpected
        }
    }

    /// The message shown to the vendor. `unexpected` defers to the caller's own wording, which is more
    /// specific than anything this type could say.
    func message(fallback: String) -> String {
        switch self {
        case .offline: String(localized: "error.offline", defaultValue: "No connection. The change is saved on this device and will sync when you're back online.")
        case .notAllowed: String(localized: "error.notAllowed", defaultValue: "You don't have access to that record. Try signing out and back in.")
        case .unexpected: fallback
        }
    }
}
