import SwiftUI
import AuthenticationServices

/// Welcome — the only screen a signed-out user sees. Apple first (App Store guideline 4.8), then Google, then email.
struct WelcomeView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.colorScheme) private var scheme
    @State private var busy = false
    @State private var error: String?
    @State private var emailSheet = false

    var body: some View {
        ZStack {
            MColor.ground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: Space.xl) {
                Spacer()
                Image("BrandMark").resizable().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Mehfil").type(.displayLg).foregroundStyle(MColor.text)
                    Text("Run the wedding season without the spreadsheet.").type(.headingMd).foregroundStyle(MColor.text)
                    Text("Every date, every rupee outstanding, every double-booking — before it becomes a problem.").type(.bodyMd).foregroundStyle(MColor.textMute)
                }
                VStack(alignment: .leading, spacing: Space.md) {
                    point("calendar", "The calendar is the spine")
                    point("indianrupeesign", "Outstanding money on the home screen")
                    point("exclamationmark.triangle", "Conflicts surface early, unprompted")
                }
                Spacer()
                VStack(spacing: Space.sm) {
                    if auth.isCloud && Features.hasCloudSignIn {
                        // A free personal team cannot provision Sign in with Apple, so device-test builds hide it (run-on-device.sh).
                        if Features[.appleSignIn] {
                            SignInWithAppleButton(.continue) { _ in } onCompletion: { _ in }
                                .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                                .frame(height: Dim.button).clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)).allowsHitTesting(false)
                                // Color.clear is not hit-testable on its own; the contentShape makes the whole button tappable.
                                .overlay(Button { run { try await auth.signInWithApple() } } label: { Color.clear.contentShape(Rectangle()) }.buttonStyle(.plain))
                        }
                        if Features[.googleSignIn] {
                            Button { run { try await auth.signInWithGoogle() } } label: {
                                HStack(spacing: Space.sm) {
                                    GoogleMark().frame(width: 18, height: 18)
                                    Text("Continue with Google").type(.buttonMd)
                                }
                                .foregroundStyle(MColor.text).frame(maxWidth: .infinity).frame(height: Dim.button)
                                .background(MColor.surface, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(MColor.lineInput, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        if Features[.emailPassword] {
                            Button { emailSheet = true } label: {
                                HStack(spacing: Space.sm) {
                                    Image(systemName: "envelope").font(.system(size: 16, weight: .medium))
                                    Text("Continue with email").type(.buttonMd)
                                }
                                .foregroundStyle(MColor.text).frame(maxWidth: .infinity).frame(height: Dim.button)
                                .background(MColor.surface, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(MColor.lineInput, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    } else if Features[.deviceOnlyMode] {
                        MButton(title: "Continue on this device", icon: "iphone") { auth.continueOnDevice() }
                        Text("This build has no cloud configuration, so your data stays on this device. See backend/README.md to enable Google, Apple and email sign-in.")
                            .type(.caption).foregroundStyle(MColor.textMute).multilineTextAlignment(.center)
                    }
                    if let error { Text(error).type(.caption).foregroundStyle(MColor.danger).multilineTextAlignment(.center) }
                    Text("By continuing you agree to the [Terms](https://sanu5.github.io/terms/) and [Privacy Policy](https://sanu5.github.io/privacy/).")
                        .type(.caption).foregroundStyle(MColor.textMute).tint(MColor.text).multilineTextAlignment(.center).padding(.top, Space.xs)
                }
            }
            .padding(.horizontal, Space.xl).padding(.bottom, Space.lg)
            if busy { MColor.scrim.ignoresSafeArea(); ProgressView().tint(.white) }
        }
        .sheet(isPresented: $emailSheet) { EmailAuthSheet() }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: Space.md) {
            Image(systemName: symbol).font(.system(size: 16, weight: .regular)).foregroundStyle(MColor.text).frame(width: Dim.icon)
            Text(text).type(.bodyMd).foregroundStyle(MColor.text)
        }
    }
    private func run(_ work: @escaping () async throws -> Void) {
        error = nil; busy = true
        Task {
            do { try await work() } catch AuthError.cancelled { } catch { self.error = AuthService.message(for: error) }
            busy = false
        }
    }
}

/// Google's four-colour G — the official geometry, as a vector asset.
struct GoogleMark: View {
    var body: some View { Image("GoogleG").resizable().scaledToFit() }
}

/// Email and password: create an account or sign in, with a password-reset path. One sheet, three modes.
struct EmailAuthSheet: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    private enum Mode { case signIn, signUp, reset }
    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    @FocusState private var focus: Field?
    private enum Field { case name, email, password, confirm }

    private var title: String {
        switch mode { case .signIn: "Sign in"; case .signUp: "Create your account"; case .reset: "Reset your password" }
    }
    private var subtitle: String {
        switch mode {
        case .signIn: "With the email and password you signed up with."
        case .signUp: "We'll email you a link to confirm the address."
        case .reset: "We'll email you a link to set a new password."
        }
    }
    private var canSubmit: Bool {
        guard AuthService.isValidEmail(email) else { return false }
        switch mode {
        case .reset: return true
        case .signIn: return !password.isEmpty
        case .signUp: return !name.trimmingCharacters(in: .whitespaces).isEmpty && AuthService.passwordProblem(password) == nil && password == confirm
        }
    }

    var body: some View {
        SheetScaffold(title: title, subtitle: subtitle) {
            if mode == .signUp {
                InputField(label: "Your name", text: $name, placeholder: "Anand Mehra").focused($focus, equals: .name)
            }
            InputField(label: "Email", text: $email, placeholder: "you@example.com", keyboard: .emailAddress).focused($focus, equals: .email)
            if mode != .reset {
                PasswordField(label: "Password", text: $password,
                              placeholder: mode == .signUp ? "At least 8 characters" : "Your password",
                              helper: mode == .signUp ? AuthService.passwordProblem(password) : nil,
                              newPassword: mode == .signUp)
            }
            if mode == .signUp {
                PasswordField(label: "Confirm password", text: $confirm, placeholder: "Type it again",
                              helper: !confirm.isEmpty && confirm != password ? "The two passwords don't match." : nil,
                              newPassword: true)
            }
            if let notice { Text(notice).type(.caption).foregroundStyle(MColor.text) }
            if let error { Text(error).type(.caption).foregroundStyle(MColor.danger) }
            HStack(spacing: Space.md) {
                switch mode {
                case .signIn:
                    Button("Create an account") { switchTo(.signUp) }.type(.buttonSm).foregroundStyle(MColor.text)
                    Spacer()
                    Button("Forgot password?") { switchTo(.reset) }.type(.buttonSm).foregroundStyle(MColor.text)
                case .signUp:
                    Button("I already have an account") { switchTo(.signIn) }.type(.buttonSm).foregroundStyle(MColor.text)
                    Spacer()
                case .reset:
                    Button("Back to sign in") { switchTo(.signIn) }.type(.buttonSm).foregroundStyle(MColor.text)
                    Spacer()
                }
            }
            .padding(.top, Space.xs)
        } actions: {
            MButton(title: mode == .signUp ? "Create account" : mode == .signIn ? "Sign in" : "Send reset link", loading: busy) { submit() }
                .disabled(!canSubmit)
        }
        .presentationDetents([.large])
        .onAppear { focus = .email }
    }

    private func switchTo(_ m: Mode) { mode = m; error = nil; notice = nil }

    private func submit() {
        guard canSubmit, !busy else { return }
        error = nil; notice = nil; busy = true
        Task {
            do {
                switch mode {
                case .signIn: try await auth.signIn(email: email, password: password); dismiss()
                case .signUp: try await auth.signUp(email: email, password: password, name: name); dismiss()
                case .reset:
                    try await auth.sendPasswordReset(to: email)
                    notice = "Sent. Open the link in your inbox, then come back and sign in."
                    mode = .signIn
                }
            } catch { self.error = AuthService.message(for: error) }
            busy = false
        }
    }
}

/// Shown after an email sign-up until the address is confirmed. Nothing else in the app is reachable from here.
struct VerifyEmailView: View {
    @Environment(AuthService.self) private var auth
    var account: Account
    @State private var busy = false
    @State private var sent = false
    @State private var error: String?
    @State private var checking = false

    var body: some View {
        ZStack {
            MColor.ground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: Space.xl) {
                Spacer()
                Image(systemName: "envelope.badge").font(.system(size: 44, weight: .light)).foregroundStyle(MColor.accent)
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Confirm your email").type(.displayMd).foregroundStyle(MColor.text)
                    Text("We sent a link to \(account.email ?? "your inbox"). Open it, then tap I've confirmed.").type(.bodyMd).foregroundStyle(MColor.textMute)
                }
                if let error { Text(error).type(.caption).foregroundStyle(MColor.danger) }
                if sent { Text("Sent again. It can take a minute — check spam too.").type(.caption).foregroundStyle(MColor.text) }
                Spacer()
                VStack(spacing: Space.sm) {
                    MButton(title: "I've confirmed", loading: checking) {
                        checking = true
                        Task {
                            let ok = await auth.refreshVerification()
                            if !ok { error = "Not confirmed yet. Open the link in your inbox first." }
                            checking = false
                        }
                    }
                    MButton(title: "Send the link again", style: .secondary, loading: busy) {
                        busy = true; error = nil
                        Task {
                            do { try await auth.sendVerificationEmail(); sent = true }
                            catch { self.error = AuthService.message(for: error) }
                            busy = false
                        }
                    }
                    MButton(title: "Sign out", style: .tertiary, size: .compact) { try? auth.signOut() }
                }
            }
            .padding(.horizontal, Space.xl).padding(.bottom, Space.lg)
        }
        // Opening the link happens in Safari or Mail, so re-check whenever the app comes back to the front.
        .task { _ = await auth.refreshVerification() }
    }
}

/// Onboarding — the business card the rest of the app is signed with.
struct OnboardingView: View {
    @Environment(AuthService.self) private var auth
    @Environment(AppStore.self) private var store
    var account: Account
    @State private var owner = ""
    @State private var business = ""
    @State private var phone = ""
    @State private var area = ""
    @State private var loadSample = true
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ScreenScaffold(title: "Set up your business", subtitle: "Signed in with \(account.providerLabel)" + (account.email.map { " · \($0)" } ?? ""), spacing: Space.lg, bottomPadding: 120) {
                InputField(label: "Your name", text: $owner, placeholder: "Anand Mehra")
                InputField(label: "Business name", text: $business, placeholder: "Mehfil Decor")
                PhoneField(text: $phone, placeholder: "98110 08123", helper: "Shown to clients on the page you share with them.")
                InputField(label: "Area", text: $area, placeholder: "Sector 44, Gurugram")
                if Features[.sampleSeason] {
                    Toggle(isOn: $loadSample) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start with a sample season").type(.bodyMdStrong).foregroundStyle(MColor.text)
                            Text("Twelve events, crew, inventory and payments to explore. You can erase it later from Profile.").type(.caption).foregroundStyle(MColor.textMute)
                        }
                    }
                    .tint(MColor.accent).padding(.top, Space.sm)
                }
            }
            .dockedActions {
                MButton(title: "Open Mehfil", loading: saving) {
                    saving = true
                    Task {
                        await store.completeOnboarding(profile: .new(owner: owner.trimmingCharacters(in: .whitespaces), business: business.trimmingCharacters(in: .whitespaces), phone: phone, area: area),
                                                       loadSample: loadSample && Features[.sampleSeason])
                        saving = false
                    }
                }
                .disabled(owner.trimmingCharacters(in: .whitespaces).isEmpty || business.trimmingCharacters(in: .whitespaces).isEmpty || !Fmt.isValidPhone(phone))
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Sign out") { try? auth.signOut() }.type(.buttonSm) } }
            .onAppear { if owner.isEmpty, let n = account.name { owner = n } }
        }
    }
}

/// Account — who is signed in, sign out, erase data, delete the account (App Store guideline 5.1.1(v)).
struct AccountView: View {
    @Environment(AuthService.self) private var auth
    @Environment(AppStore.self) private var store
    @State private var confirmErase = false
    @State private var confirmRemoveSample = false
    @State private var confirmDelete = false
    @State private var passwordSheet = false
    @State private var deletePassword = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        let account = auth.account
        ScreenScaffold(title: "Account", subtitle: account.map { "\($0.providerLabel)" + ($0.email.map { " · \($0)" } ?? "") }, spacing: Space.lg) {
            RowGroup {
                ListRow(title: account?.name ?? store.vendor?.ownerName ?? "You", subtitle: account?.email ?? (auth.isCloud ? "Signed in" : "On this device only")) {
                    IconTile(symbol: "person")
                } trailing: { EmptyView() }
                Hairline(inset: 68)
                ListRow(title: "Storage", subtitle: auth.isCloud ? "Synced to your Mehfil cloud account" : "This device — not backed up") {
                    IconTile(symbol: auth.isCloud ? "icloud" : "iphone")
                } trailing: { EmptyView() }
                if account?.provider == "password" {
                    Hairline(inset: 68)
                    Button { passwordSheet = true } label: {
                        ListRow(title: "Change password", subtitle: "You'll confirm the current one first") { IconTile(symbol: "key") } trailing: { Chevron() }
                    }.buttonStyle(.plain)
                }
            }
            RowGroup {
                if Features[.sampleSeason] {
                    Button { Task { await store.loadSampleSeason() } } label: {
                        ListRow(title: "Load the sample season", subtitle: "Adds the demo events, crew and payments") { IconTile(symbol: "sparkles") } trailing: { Chevron() }
                    }.buttonStyle(.plain)
                    Hairline(inset: 68)
                }
                if Features[.removeSampleSeason] {
                    Button { confirmRemoveSample = true } label: {
                        ListRow(title: "Remove the sample season", subtitle: "Deletes only the demo records — your own work stays") { IconTile(symbol: "sparkles.slash") } trailing: { Chevron() }
                    }.buttonStyle(.plain)
                    Hairline(inset: 68)
                }
                Button { confirmErase = true } label: {
                    ListRow(title: "Erase all data", subtitle: "Events, clients, crew, inventory and payments") { IconTile(symbol: "trash", color: MColor.danger) } trailing: { Chevron() }
                }.buttonStyle(.plain)
            }
            VStack(spacing: Space.sm) {
                MButton(title: "Sign out", style: .secondary) { try? auth.signOut() }
                MButton(title: "Delete account", style: .destructive) {
                    if account?.provider == "password" { deletePassword = ""; confirmDelete = true } else { confirmDelete = true }
                }
                if let error { Text(error).type(.caption).foregroundStyle(MColor.danger).multilineTextAlignment(.center) }
            }
            .padding(.top, Space.md)
            Text("Deleting removes your account and every event, client, crew member and payment record. It cannot be undone.")
                .type(.caption).foregroundStyle(MColor.textMute)
            HStack(spacing: Space.lg) {
                Link("Privacy Policy", destination: URL(string: "https://sanu5.github.io/privacy/")!)
                Link("Terms", destination: URL(string: "https://sanu5.github.io/terms/")!)
            }
            .type(.caption).tint(MColor.text)
        }
        .overlay { if busy { ZStack { MColor.scrim.ignoresSafeArea(); ProgressView().tint(.white) } } }
        .sheet(isPresented: $passwordSheet) { ChangePasswordSheet() }
        .sheet(isPresented: $confirmRemoveSample) {
            SheetScaffold(title: "Remove the sample season?", subtitle: "The twelve demo events and their clients, crew, inventory, payments and tasks go. Anything you created yourself stays exactly as it is.") { EmptyView() } actions: {
                VStack(spacing: Space.sm) {
                    MButton(title: "Remove the sample data", style: .destructive) { confirmRemoveSample = false; perform { await store.removeSampleSeason() } }
                    MButton(title: "Keep it", style: .tertiary, size: .compact) { confirmRemoveSample = false }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $confirmErase) {
            SheetScaffold(title: "Erase everything in \(store.vendor?.businessName ?? "Mehfil")?", subtitle: "Every event, client, crew member, item and payment record goes. Your account and profile stay.") { EmptyView() } actions: {
                VStack(spacing: Space.sm) {
                    MButton(title: "Erase all data", style: .destructive) { confirmErase = false; perform { try await store.eraseAllData(); store.show(.info, "All data erased") } }
                    MButton(title: "Keep it", style: .tertiary, size: .compact) { confirmErase = false }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $confirmDelete) {
            SheetScaffold(title: "Delete your Mehfil account?", subtitle: "\(store.vendor?.businessName ?? "Your business") and all its records are deleted permanently.") {
                if auth.account?.provider == "password" {
                    PasswordField(label: "Confirm your password", text: $deletePassword, placeholder: "Your password",
                                  helper: "Firebase needs a fresh sign-in before deleting an account.")
                }
            } actions: {
                VStack(spacing: Space.sm) {
                    MButton(title: "Delete account and data", style: .destructive) {
                        confirmDelete = false
                        perform { try await store.eraseAllData(); try await auth.deleteAccount(password: deletePassword.nilIfEmpty) }
                    }
                    .disabled(auth.account?.provider == "password" && deletePassword.isEmpty)
                    MButton(title: "Keep my account", style: .tertiary, size: .compact) { confirmDelete = false }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func perform(_ work: @escaping () async throws -> Void) {
        error = nil; busy = true
        Task {
            do { try await work() } catch AuthError.cancelled { } catch { self.error = AuthService.message(for: error) }
            busy = false
        }
    }
}

/// Change password — current, new, confirm.
struct ChangePasswordSheet: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var error: String?

    private var canSubmit: Bool { !current.isEmpty && AuthService.passwordProblem(new) == nil && new == confirm }

    var body: some View {
        SheetScaffold(title: "Change password", subtitle: "You'll stay signed in on this device.") {
            PasswordField(label: "Current password", text: $current, placeholder: "Your current password")
            PasswordField(label: "New password", text: $new, placeholder: "At least 8 characters", helper: AuthService.passwordProblem(new), newPassword: true)
            PasswordField(label: "Confirm new password", text: $confirm, placeholder: "Type it again",
                          helper: !confirm.isEmpty && confirm != new ? "The two passwords don't match." : nil, newPassword: true)
            if let error { Text(error).type(.caption).foregroundStyle(MColor.danger) }
        } actions: {
            MButton(title: "Save password", loading: busy) {
                busy = true; error = nil
                Task {
                    do { try await auth.changePassword(current: current, new: new); dismiss() }
                    catch { self.error = AuthService.message(for: error) }
                    busy = false
                }
            }
            .disabled(!canSubmit)
        }
        .presentationDetents([.medium, .large])
    }
}

