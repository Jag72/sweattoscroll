// FamilyActivitySelection+Sanitize.swift
// Never apply Screen Time shields to this host app. Apple's Family Activity
// picker cannot grey-out individual entries; we strip them immediately after
// selection using ManagedSettings.Application(bundleIdentifier:).

import Foundation
import FamilyControls
import ManagedSettings

enum RestrictedAppsPolicy {

    private static let appGroupID = "group.com.sweat2scroll.appblocker"

    static var forbiddenBundleIdentifiers: Set<String> {
        var ids = Set<String>()
        let suite = UserDefaults(suiteName: appGroupID)

        if let host = suite?.string(forKey: AppGroupKey.hostAppBundleIdentifier), !host.isEmpty {
            ids.insert(host.lowercased())
            return ids
        }

        // Main app only — before the App Group key exists on disk.
        if let bid = Bundle.main.bundleIdentifier, !bid.isEmpty {
            ids.insert(bid.lowercased())
        }
        return ids
    }
}

extension FamilyActivitySelection {

    /// Drops application tokens whose resolved bundle ID matches the forbidden set.
    func excludingForbiddenApplications(_ forbidden: Set<String>) -> FamilyActivitySelection {
        let forbiddenLower = Set(forbidden.map { $0.lowercased() })
        guard !forbiddenLower.isEmpty else { return self }

        let filtered = applicationTokens.filter { token in
            let bid = Application(token: token).bundleIdentifier?.lowercased() ?? ""
            return !forbiddenLower.contains(bid)
        }

        guard filtered.count != applicationTokens.count else { return self }

        var copy = self
        copy.applicationTokens = Set(filtered)
        return copy
    }

    /// Convenience: removes this app's bundle ID from the selection.
    func excludingHostApplication() -> FamilyActivitySelection {
        excludingForbiddenApplications(RestrictedAppsPolicy.forbiddenBundleIdentifiers)
    }
}
