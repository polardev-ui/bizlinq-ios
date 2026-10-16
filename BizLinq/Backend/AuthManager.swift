import AuthenticationServices
import CryptoKit
import Foundation

/// Sign in with Apple -> Supabase session. Browsing stays guest-friendly;
/// posting and RSVPing require a signed-in user. Session tokens live in the
/// Keychain; only the access token is kept in memory.
@MainActor
final class AuthManager: ObservableObject {
    private enum Keys {
        static let sessionAccount = "bizlinq.supabase.session"
    }

    @Published var userID: UUID?
    @Published var displayName: String = ""
    @Published var isWorking: Bool = false
    @Published var lastError: String?

    let client: SupabaseRESTClient

    init(client: SupabaseRESTClient) {
        self.client = client
        Task { await restoreSession() }
    }

    var isSignedIn: Bool { userID != nil }

    func restoreSession() async {
        guard let data = Keychain.load(account: Keys.sessionAccount),
              let saved = try? JSONDecoder().decode(SupabaseRESTClient.Session.self, from: data) else {
            return
        }
        client.session = saved
        do {
            let valid = try await client.refreshSession()
            persist(session: valid)
            userID = valid.userID
            await loadProfile()
        } catch {
            client.session = nil
            Keychain.delete(account: Keys.sessionAccount)
        }
    }

    func signInWithApple(idToken: String, nonce: String, suggestedName: String?) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let session = try await client.signInWithApple(idToken: idToken, nonce: nonce)
            persist(session: session)
            userID = session.userID
            await loadProfile()
            if let suggestedName, !suggestedName.isEmpty, displayName.isEmpty {
                await saveDisplayName(suggestedName)
            }
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func signOut() async {
        await client.signOut()
        Keychain.delete(account: Keys.sessionAccount)
        userID = nil
        displayName = ""
    }

    func loadProfile() async {
        guard let userID else { return }
        do {
            if let row = try await client.fetchProfile(id: userID) {
                displayName = row.displayName ?? ""
            }
        } catch {
            // No profile row yet (first sign-in) - created on first save.
        }
    }

    func saveDisplayName(_ name: String) async {
        guard let userID else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await client.upsertProfile(ProfileRow(id: userID, displayName: trimmed, homeZip: nil, radiusMiles: nil))
            displayName = trimmed
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func saveHomeLocation(zip: String, radiusMiles: Int?) async {
        guard let userID else { return }
        do {
            try await client.upsertProfile(ProfileRow(
                id: userID,
                displayName: displayName.isEmpty ? nil : displayName,
                homeZip: zip,
                radiusMiles: radiusMiles
            ))
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func persist(session: SupabaseRESTClient.Session) {
        if let data = try? JSONEncoder().encode(session) {
            Keychain.save(data, account: Keys.sessionAccount)
        }
    }

    // MARK: - Apple nonce helpers

    static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
