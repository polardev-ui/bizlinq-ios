import Foundation

/// On-device facts for support and review debugging (shown in Profile).
/// Reads the embedded provisioning profile to prove whether a capability
/// actually made it into the build the user is running.
enum AppDiagnostics {
    static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "unknown"
    }

    static var versionBuild: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "?"
        return "\(v) (\(b))"
    }

    private static var embeddedEntitlements: [String: Any]? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let xmlStart = data.range(of: Data("<?xml".utf8)),
              let plistEnd = data.range(of: Data("</plist>".utf8)) else {
            return nil
        }
        let xml = data[xmlStart.lowerBound..<plistEnd.upperBound]
        let plist = (try? PropertyListSerialization.propertyList(from: xml, format: nil)) as? [String: Any]
        return plist?["Entitlements"] as? [String: Any]
    }

    /// nil on simulator (no provisioning profile there — expected).
    static var signInCapabilityInProfile: Bool? {
        guard let entitlements = embeddedEntitlements else { return nil }
        return (entitlements["com.apple.developer.applesignin"] as? [String]) != nil
    }

    static var teamPrefix: String? {
        guard let entitlements = embeddedEntitlements else { return nil }
        return (entitlements["application-identifier"] as? String)?
            .split(separator: ".").first.map(String.init)
    }
}
