import OSLog

/// Unified logging, one category per area.
///
/// `print` writes to stdout on every build and is invisible in Console.app on a device; `Logger` is
/// level-filtered, survives release builds, and redacts interpolations by default — which is what keeps
/// document ids and vendor data out of the system log.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.anish.mehfil"

    static let store = Logger(subsystem: subsystem, category: "store")
    static let repository = Logger(subsystem: subsystem, category: "repository")
    static let auth = Logger(subsystem: subsystem, category: "auth")
}
