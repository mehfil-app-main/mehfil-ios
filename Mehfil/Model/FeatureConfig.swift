import Foundation

/// Every switchable capability in the app, in one place.
///
/// Defaults are the shipping configuration. To change what a build ships with, edit `defaultValue`
/// below — nothing else in the app hard-codes these decisions.
///
/// In DEBUG builds each flag can also be flipped at runtime from Profile → Account → Feature flags
/// (or from a test with `Features.override(.emailPassword, false)`), which makes QA and demos
/// possible without a rebuild. Release builds always use `defaultValue` and ignore overrides.
enum Feature: String, CaseIterable, Identifiable {

    // MARK: Sign-in methods

    /// Sign in with Apple. Required by App Store guideline 4.8 whenever Google sign-in is offered,
    /// so this must stay on for any App Store build. A free personal Apple team cannot provision the
    /// capability, so `run-on-device.sh` compiles it out with `-D PERSONAL_TEAM` instead.
    case appleSignIn
    /// Continue with Google (GoogleSignIn SDK + Firebase).
    case googleSignIn
    /// Email and password, with a verification email before the account can be used.
    case emailPassword
    /// Require a verified email address before the app opens. Turning this off lets unverified
    /// accounts straight in — convenient in testing, not recommended in production.
    case emailVerificationRequired
    /// "Continue on this device" — the offline account used when no Firebase config is bundled.
    /// Leave on: it is what lets the app run, and be reviewed, before the buyer wires up Firebase.
    case deviceOnlyMode

    // MARK: Product modules
    //
    // Each of these hides a whole area of the app: its rows, its routes and its entry points.
    // They exist so a buyer can ship a narrower first version without deleting code.

    /// Offer the twelve-event demo season: the onboarding toggle and the Account row that loads it.
    /// Off by default — a buyer's production build should not ship demo data behind a one-tap button.
    case sampleSeason
    /// Offer "Remove the sample season" in Account: deletes exactly the demo records by their fixed ids and
    /// leaves everything the vendor entered untouched. Off by default, for the same reason.
    case removeSampleSeason
    /// Inventory: stock items, per-date holds, the commitment strip.
    case inventory
    /// Runsheet: the per-event task list with blocks, reorder and completion.
    case runsheet
    /// Expenses and the per-event margin.
    case expenses
    /// Enquiries: intake, conflict check, convert-to-event.
    case enquiries
    /// Package templates used when quoting.
    case packages
    /// Change requests with their costed impact and revised quote.
    case changeRequests
    /// The client-facing shared event page and its share sheet.
    case sharedClientPage
    /// Reminders composed in three tones, sent over WhatsApp or SMS.
    case paymentReminders
    /// Dark appearance and the Appearance picker. Off pins the app to light.
    case darkMode

    var id: String { rawValue }

    /// What a release build uses.
    var defaultValue: Bool {
        switch self {
        case .appleSignIn: true
        case .googleSignIn: true
        case .emailPassword: true
        case .emailVerificationRequired: true
        case .deviceOnlyMode: true
        case .sampleSeason: false
        case .removeSampleSeason: false
        case .inventory: true
        case .runsheet: true
        case .expenses: true
        case .enquiries: true
        case .packages: true
        case .changeRequests: true
        case .sharedClientPage: true
        case .paymentReminders: true
        case .darkMode: true
        }
    }

    var title: String {
        switch self {
        case .appleSignIn: "Sign in with Apple"
        case .googleSignIn: "Continue with Google"
        case .emailPassword: "Email and password"
        case .emailVerificationRequired: "Require a verified email"
        case .deviceOnlyMode: "Continue on this device"
        case .sampleSeason: "Load the sample season"
        case .removeSampleSeason: "Remove the sample season"
        case .inventory: "Inventory"
        case .runsheet: "Runsheet"
        case .expenses: "Expenses"
        case .enquiries: "Enquiries"
        case .packages: "Package templates"
        case .changeRequests: "Change requests"
        case .sharedClientPage: "Client page"
        case .paymentReminders: "Payment reminders"
        case .darkMode: "Dark appearance"
        }
    }
}

/// Reads feature flags. `Features[.inventory]` anywhere in the app.
enum Features {
    private static let overrideKey = "featureOverrides"

    /// True when the feature is on for this build.
    static subscript(_ feature: Feature) -> Bool {
        #if DEBUG
        if let stored = overrides[feature.rawValue] { return stored }
        #endif
        // Apple's capability cannot be provisioned by a free personal team; run-on-device.sh sets this.
        #if PERSONAL_TEAM
        if feature == .appleSignIn { return false }
        #endif
        return feature.defaultValue
    }

    /// True when at least one cloud sign-in method is available — i.e. the welcome screen has something to show.
    static var hasCloudSignIn: Bool { self[.appleSignIn] || self[.googleSignIn] || self[.emailPassword] }

    // MARK: Debug overrides

    static var overrides: [String: Bool] {
        get { UserDefaults.standard.dictionary(forKey: overrideKey) as? [String: Bool] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: overrideKey) }
    }

    /// Flips a flag for this install (DEBUG only; release builds ignore it).
    static func override(_ feature: Feature, _ value: Bool?) {
        var current = overrides
        if let value { current[feature.rawValue] = value } else { current.removeValue(forKey: feature.rawValue) }
        overrides = current
    }

    /// Drops every override, returning the build to its shipping configuration.
    static func resetOverrides() { UserDefaults.standard.removeObject(forKey: overrideKey) }

    /// True when the flag differs from what a release build would use.
    static func isOverridden(_ feature: Feature) -> Bool { overrides[feature.rawValue] != nil }
}
