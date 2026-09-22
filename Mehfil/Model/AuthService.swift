import Foundation
import SwiftUI
import Observation
import AuthenticationServices
import CryptoKit
import FirebaseCore
import FirebaseAuth
import GoogleSignIn

struct Account: Equatable {
    var uid: String
    var name: String?
    var email: String?
    var provider: String        // "apple.com" | "google.com" | "password" | "device"
    /// False only for an email/password account whose verification link has not been opened yet.
    var emailVerified: Bool

    var providerLabel: String {
        switch provider {
        case "apple.com": "Apple"
        case "google.com": "Google"
        case "password": "Email"
        default: "This device"
        }
    }
}

enum AuthError: LocalizedError {
    case cancelled, noToken, noPresenter, notConfigured, appleUnavailable, notSignedIn, weakPassword, passwordMismatch
    var errorDescription: String? {
        switch self {
        case .cancelled: "Sign-in was cancelled."
        case .noToken: "The sign-in provider did not return a token."
        case .noPresenter: "Nothing to present the sign-in from."
        case .notConfigured: "Cloud sign-in is not configured in this build."
        case .appleUnavailable: "Sign in with Apple isn't available here. Sign in to an Apple Account in Settings first, then try again."
        case .notSignedIn: "You're not signed in."
        case .weakPassword: "Use at least 8 characters, with a letter and a number."
        case .passwordMismatch: "The two passwords don't match."
        }
    }
}

/// Firebase Auth when the build has a config; otherwise a single on-device account so the app still works.
@Observable
final class AuthService {
    enum State: Equatable { case loading, signedOut, signedIn(Account) }
    private(set) var state: State = .loading
    let isCloud: Bool
    private var listener: AuthStateDidChangeListenerHandle?
    private var appleCoordinator: AppleSignInCoordinator?
    private static let localKey = "localAccountActive"

    init() {
        isCloud = Backend.isConfigured
        if isCloud {
            if let clientID = FirebaseApp.app()?.options.clientID { GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID) }
            listener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
                self?.state = user.map { .signedIn(Self.account(from: $0)) } ?? .signedOut
            }
        } else {
            state = UserDefaults.standard.bool(forKey: Self.localKey) ? .signedIn(Self.localAccount) : .signedOut
        }
    }

    var account: Account? { if case .signedIn(let a) = state { return a }; return nil }
    static let localAccount = Account(uid: "local-device", name: nil, email: nil, provider: "device", emailVerified: true)

    /// True when the signed-in account still has to open its verification link before using the app.
    var needsEmailVerification: Bool {
        guard Features[.emailVerificationRequired], let a = account else { return false }
        return a.provider == "password" && !a.emailVerified
    }

    private static func account(from user: User) -> Account {
        let provider = user.providerData.first(where: { $0.providerID != "firebase" })?.providerID ?? "firebase"
        return Account(uid: user.uid, name: user.displayName, email: user.email, provider: provider,
                       // Only a password account can be unverified; federated providers vouch for the address.
                       emailVerified: provider == "password" ? user.isEmailVerified : true)
    }

    // MARK: Device-only account (no Firebase config)

    func continueOnDevice() {
        UserDefaults.standard.set(true, forKey: Self.localKey)
        state = .signedIn(Self.localAccount)
    }

    // MARK: Email and password

    /// Minimum we accept: 8 characters with at least one letter and one digit.
    static func passwordProblem(_ password: String) -> String? {
        if password.count < 8 { return "Use at least 8 characters." }
        if !password.contains(where: \.isLetter) { return "Include at least one letter." }
        if !password.contains(where: \.isNumber) { return "Include at least one number." }
        return nil
    }

    static func isValidEmail(_ email: String) -> Bool {
        let t = email.trimmingCharacters(in: .whitespaces)
        guard let at = t.firstIndex(of: "@"), t.firstIndex(of: "@") == t.lastIndex(of: "@") else { return false }
        let local = t[t.startIndex..<at], domain = t[t.index(after: at)...]
        return !local.isEmpty && domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".") && !t.contains(" ")
    }

    /// Creates the account, stores the owner's name on it and sends the verification email.
    @MainActor
    func signUp(email: String, password: String, name: String) async throws {
        guard isCloud else { throw AuthError.notConfigured }
        let result = try await Auth.auth().createUser(withEmail: email.trimmingCharacters(in: .whitespaces), password: password)
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            let change = result.user.createProfileChangeRequest()
            change.displayName = trimmed
            try? await change.commitChanges()
        }
        try? await result.user.sendEmailVerification()
        state = .signedIn(Self.account(from: result.user))
    }

    @MainActor
    func signIn(email: String, password: String) async throws {
        guard isCloud else { throw AuthError.notConfigured }
        let result = try await Auth.auth().signIn(withEmail: email.trimmingCharacters(in: .whitespaces), password: password)
        state = .signedIn(Self.account(from: result.user))
    }

    /// Sends (or resends) the verification email for the signed-in account.
    func sendVerificationEmail() async throws {
        guard let user = Auth.auth().currentUser else { throw AuthError.notSignedIn }
        try await user.sendEmailVerification()
    }

    /// Pulls the user record again so `emailVerified` reflects a link opened elsewhere.
    @MainActor @discardableResult
    func refreshVerification() async -> Bool {
        guard let user = Auth.auth().currentUser else { return false }
        try? await user.reload()
        guard let fresh = Auth.auth().currentUser else { return false }
        state = .signedIn(Self.account(from: fresh))
        return fresh.isEmailVerified
    }

    func sendPasswordReset(to email: String) async throws {
        guard isCloud else { throw AuthError.notConfigured }
        try await Auth.auth().sendPasswordReset(withEmail: email.trimmingCharacters(in: .whitespaces))
    }

    /// Changes the password after confirming the current one.
    func changePassword(current: String, new: String) async throws {
        guard let user = Auth.auth().currentUser, let email = user.email else { throw AuthError.notSignedIn }
        try await user.reauthenticate(with: EmailAuthProvider.credential(withEmail: email, password: current))
        try await user.updatePassword(to: new)
    }

    /// Firebase's email/password errors in plain words.
    static func message(for error: Error) -> String {
        let e = error as NSError
        guard e.domain == AuthErrorDomain, let code = AuthErrorCode(rawValue: e.code) else { return error.localizedDescription }
        switch code {
        case .invalidEmail: return "That doesn't look like an email address."
        case .emailAlreadyInUse: return "An account already exists for this email. Sign in instead."
        case .weakPassword: return "That password is too easy to guess. Use at least 8 characters with a letter and a number."
        case .wrongPassword, .invalidCredential: return "Wrong email or password."
        case .userNotFound: return "No account for that email. Create one first."
        case .userDisabled: return "This account has been disabled."
        case .tooManyRequests: return "Too many attempts. Wait a few minutes and try again."
        case .networkError: return "No connection. Check your internet and try again."
        case .requiresRecentLogin: return "Please sign in again before making this change."
        case .credentialAlreadyInUse, .accountExistsWithDifferentCredential:
            return "This email is already used by another sign-in method. Use that one instead."
        default: return error.localizedDescription
        }
    }

    // MARK: Sign in with Apple

    @MainActor
    func signInWithApple() async throws {
        guard isCloud else { throw AuthError.notConfigured }
        let nonce = Self.randomNonce()
        let (credential, _) = try await requestApple(nonce: nonce)
        guard let tokenData = credential.identityToken, let idToken = String(data: tokenData, encoding: .utf8) else { throw AuthError.noToken }
        let firebaseCredential = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: nonce, fullName: credential.fullName)
        let result = try await Auth.auth().signIn(with: firebaseCredential)
        // Apple only sends the name on the first authorization; keep it on the Firebase user.
        if result.user.displayName == nil, let name = credential.fullName, let formatted = PersonNameComponentsFormatter().string(from: name).nilIfEmpty {
            let change = result.user.createProfileChangeRequest(); change.displayName = formatted; try? await change.commitChanges()
            state = .signedIn(Self.account(from: result.user))
        }
    }

    @MainActor
    private func requestApple(nonce: String) async throws -> (ASAuthorizationAppleIDCredential, String?) {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
        let coordinator = AppleSignInCoordinator()
        appleCoordinator = coordinator
        defer { appleCoordinator = nil }
        return try await coordinator.perform(request)
    }

    // MARK: Google

    @MainActor
    func signInWithGoogle() async throws {
        guard isCloud else { throw AuthError.notConfigured }
        guard let presenter = Self.topViewController() else { throw AuthError.noPresenter }
        let result: GIDSignInResult
        do { result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter) }
        catch let e as NSError where e.code == GIDSignInError.canceled.rawValue { throw AuthError.cancelled }
        guard let idToken = result.user.idToken?.tokenString else { throw AuthError.noToken }
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
        try await Auth.auth().signIn(with: credential)
    }

    // MARK: Sign out / delete

    func signOut() throws {
        if isCloud {
            GIDSignIn.sharedInstance.signOut()
            try Auth.auth().signOut()
        } else {
            UserDefaults.standard.set(false, forKey: Self.localKey)
            state = .signedOut
        }
    }

    /// Deletes the Firebase user. Re-authenticates first (Firebase requires a recent sign-in) and revokes the
    /// Sign in with Apple token, as App Store Review requires. The caller deletes the vendor's data beforehand.
    ///
    /// `password` is required only for email/password accounts — the UI asks for it before calling.
    @MainActor
    func deleteAccount(password: String? = nil) async throws {
        guard isCloud else { UserDefaults.standard.set(false, forKey: Self.localKey); state = .signedOut; return }
        guard let user = Auth.auth().currentUser else { return }
        switch user.providerData.first?.providerID ?? "" {
        case "apple.com":
            let nonce = Self.randomNonce()
            let (credential, code) = try await requestApple(nonce: nonce)
            guard let tokenData = credential.identityToken, let idToken = String(data: tokenData, encoding: .utf8) else { throw AuthError.noToken }
            try await user.reauthenticate(with: OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: nonce, fullName: nil))
            if let code { try? await Auth.auth().revokeToken(withAuthorizationCode: code) }
        case "google.com":
            guard let presenter = Self.topViewController() else { throw AuthError.noPresenter }
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else { throw AuthError.noToken }
            try await user.reauthenticate(with: GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString))
        case "password":
            guard let email = user.email, let password else { throw AuthError.notSignedIn }
            try await user.reauthenticate(with: EmailAuthProvider.credential(withEmail: email, password: password))
        default: break
        }
        try await user.delete()
        GIDSignIn.sharedInstance.signOut()
    }

    func handle(url: URL) -> Bool { isCloud ? GIDSignIn.sharedInstance.handle(url) : false }

    // MARK: Helpers

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }
    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    @MainActor
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard var top = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}

/// Bridges ASAuthorizationController's delegate to async/await.
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<(ASAuthorizationAppleIDCredential, String?), Error>?

    @MainActor
    func perform(_ request: ASAuthorizationAppleIDRequest) async throws -> (ASAuthorizationAppleIDCredential, String?) {
        try await withCheckedThrowingContinuation { cont in
            continuation = cont
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { continuation?.resume(throwing: AuthError.noToken); return }
        let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        continuation?.resume(returning: (credential, code)); continuation = nil
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let e = error as? ASAuthorizationError {
            switch e.code {
            case .canceled: continuation?.resume(throwing: AuthError.cancelled)
            // 1000: no Apple Account on this device/simulator, or the app was built without the Sign in with Apple entitlement.
            case .unknown: continuation?.resume(throwing: AuthError.appleUnavailable)
            default: continuation?.resume(throwing: error)
            }
        } else { continuation?.resume(throwing: error) }
        continuation = nil
    }
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
