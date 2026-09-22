import SwiftUI
import FirebaseCore

@main
struct MehfilApp: App {
    @State private var auth: AuthService
    @State private var store: AppStore

    init() {
        // The Firebase config (GoogleService-Info.plist) is not committed; without it the app runs on-device only.
        if Backend.isConfigured { FirebaseApp.configure() }
        let repo: Repository = Backend.isConfigured ? FirestoreRepository() : LocalRepository()
        _auth = State(initialValue: AuthService())
        _store = State(initialValue: AppStore(repo: repo))
    }

    var body: some Scene {
        WindowGroup {
            SessionView()
                .environment(auth)
                .environment(store)
                .preferredColorScheme(scheme)
                .tint(MColor.accent)
                .onOpenURL { _ = auth.handle(url: $0) }
        }
    }

    private var scheme: ColorScheme? {
        switch store.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Routes the session: loading → welcome (signed out) → onboarding (no profile yet) → the app.
struct SessionView: View {
    @Environment(AuthService.self) private var auth
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            switch auth.state {
            case .loading:
                SplashView()
            case .signedOut:
                WelcomeView()
            case .signedIn(let account):
                if !store.profileChecked || store.uid != account.uid {
                    SplashView().task(id: account.uid) { await store.bind(uid: account.uid) }
                } else if auth.needsEmailVerification {
                    VerifyEmailView(account: account)
                } else if store.needsOnboarding {
                    OnboardingView(account: account)
                } else {
                    RootView()
                }
            }
        }
        .onChange(of: auth.state) { _, new in if case .signedOut = new { store.unbind() } }
        .animation(.easeInOut(duration: 0.25), value: store.needsOnboarding)
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            MColor.ground.ignoresSafeArea()
            VStack(spacing: Space.md) {
                Image("BrandMark").resizable().frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                ProgressView().tint(MColor.textMute)
            }
        }
    }
}
