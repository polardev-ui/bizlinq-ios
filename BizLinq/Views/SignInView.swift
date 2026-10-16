import AuthenticationServices
import SwiftUI

/// Sign in with Apple. Required for posting and RSVPing; browsing stays free.
struct SignInView: View {
    @EnvironmentObject private var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var nonce: String = ""

    var prompt: String = "Sign in to post meetings and RSVP. Browsing stays free without an account."

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(Color.teal.opacity(0.15))
                        .frame(width: 88, height: 88)
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.teal)
                }
                VStack(spacing: 6) {
                    Text("Welcome to BizLinq")
                        .font(.title.bold())
                    Text(prompt)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                SignInWithAppleButton(.signIn) { request in
                    let raw = AuthManager.randomNonceString()
                    nonce = raw
                    request.requestedScopes = []
                    request.nonce = AuthManager.sha256(raw)
                } onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                              let data = credential.identityToken,
                              let token = String(data: data, encoding: .utf8) else {
                            auth.lastError = "Apple sign-in did not return a credential."
                            return
                        }
                        let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                            .compactMap { $0 }
                            .joined(separator: " ")
                        Task {
                            await auth.signInWithApple(idToken: token, nonce: nonce, suggestedName: name.isEmpty ? nil : name)
                            if auth.userID != nil {
                                dismiss()
                            }
                        }
                    case .failure(let error):
                        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                            break // User dismissed the sheet; not an error.
                        } else if let authError = error as? ASAuthorizationError, authError.code == .unknown {
                            auth.lastError = "Apple couldn't start sign-in (error 1000). This usually means Sign in with Apple isn't enabled for this App ID yet — check Apple Developer → Identifiers → com.bizlinq.app, then rebuild and try again."
                        } else {
                            auth.lastError = error.localizedDescription
                        }
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .padding(.horizontal)

                if auth.isWorking {
                    ProgressView()
                }
                if let error = auth.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Button("Continue browsing without signing in") {
                    dismiss()
                }
                .font(.subheadline)
                Spacer()
            }
            .padding()
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
