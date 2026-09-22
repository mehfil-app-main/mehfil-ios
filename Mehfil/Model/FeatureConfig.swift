import Foundation

/// Every switchable capability in the app, in one place.
///
/// These are **build-time** decisions: edit `defaultValue` below and rebuild. There is deliberately no
/// in-app switchboard — a shipped app should not let anyone turn parts of itself on and off, and a buyer
/// reading this file sees the whole configuration surface at once.
enum Feature {

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

    /// What this build ships with. This is the only place any of these decisions is made.
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

}

/// Reads feature flags. `Features[.inventory]` anywhere in the app.
enum Features {
    static subscript(_ feature: Feature) -> Bool {
        // Apple's capability cannot be provisioned by a free personal team; run-on-device.sh sets this.
        #if PERSONAL_TEAM
        if feature == .appleSignIn { return false }
        #endif
        return feature.defaultValue
    }

    /// True when at least one cloud sign-in method is available — i.e. the welcome screen has something to show.
    static var hasCloudSignIn: Bool { self[.appleSignIn] || self[.googleSignIn] || self[.emailPassword] }
}
