import Foundation

/// Backend connection details for the BizLinq Production Supabase project.
/// The anon key is publishable by design (it ships inside the app); all
/// real protection comes from the Postgres Row Level Security policies.
/// Never put the service_role key here or anywhere in the client.
enum BackendConfig {
    // TODO(production): fill in once the BizLinq Production project is provisioned.
    static let projectURL = URL(string: "https://qzmtchjjmcdlzwwfvrwd.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InF6bXRjaGpqbWNkbHp3d2Z2cndkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE1Nzk1OTQsImV4cCI6MjEwNzE1NTU5NH0.uGwkuyFX6cCbOeuQ0x-k3nOiU7K07LQA-_jY2asXPFI"
}
