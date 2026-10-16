import Foundation

/// Reads the IAB TCF v2 in-app consent that a CMP (e.g. Usercentrics) writes to `UserDefaults`
/// and derives what the SDK is allowed to do.
///
/// The CMP persists the standard decoded keys — `IABTCF_TCString`, `IABTCF_gdprApplies` and
/// `IABTCF_PurposeConsents`. The feed's ad layer (Prebid) reads the TC string through the
/// `__tcfapi` bridge injected by ``BtaFeedView``; first-party analytics is gated by
/// ``analyticsAllowed``.
enum BtaConsent {

    private enum Key {
        static let tcString = "IABTCF_TCString"
        static let gdprApplies = "IABTCF_gdprApplies"
        static let purposeConsents = "IABTCF_PurposeConsents"
    }

    /// The raw TC string a CMP stored, or `nil` when none is present.
    static var tcString: String? {
        let value = UserDefaults.standard.string(forKey: Key.tcString)
        return (value?.isEmpty == false) ? value : nil
    }

    /// Whether GDPR applies. `1` = applies, `0` = does not. Absent but a TC string exists → applies.
    static var gdprApplies: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Key.gdprApplies) != nil {
            return defaults.integer(forKey: Key.gdprApplies) == 1
        }
        return tcString != nil
    }

    /// The decoded IAB TCF v2 consent the CMP wrote to `UserDefaults`, as needed to synthesise a
    /// full `TCData` object for the `__tcfapi` bridge. The binary `*Consents`/`*LegitimateInterests`
    /// fields are the standard "1"/"0"-per-index strings (purpose/vendor/special-feature id → bit).
    struct TcfData {
        let tcString: String
        let gdprApplies: Bool
        let purposeConsents: String
        let purposeLegitimateInterests: String
        let vendorConsents: String
        let vendorLegitimateInterests: String
        let specialFeatureOptins: String
        let publisherConsent: String
        let publisherLegitimateInterests: String
        let publisherCC: String
        let purposeOneTreatment: Bool
        let cmpId: Int
        let tcfPolicyVersion: Int
    }

    /// Reads the full decoded TCF consent from storage, or `nil` when no TC string is stored.
    static var tcfData: TcfData? {
        guard let tc = tcString else { return nil }
        let d = UserDefaults.standard
        func str(_ key: String) -> String { d.string(forKey: key) ?? "" }
        func int(_ key: String, _ fallback: Int) -> Int {
            d.object(forKey: key) != nil ? d.integer(forKey: key) : fallback
        }
        return TcfData(
            tcString: tc,
            gdprApplies: gdprApplies,
            purposeConsents: str(Key.purposeConsents),
            purposeLegitimateInterests: str("IABTCF_PurposeLegitimateInterests"),
            vendorConsents: str("IABTCF_VendorConsents"),
            vendorLegitimateInterests: str("IABTCF_VendorLegitimateInterests"),
            specialFeatureOptins: str("IABTCF_SpecialFeaturesOptins"),
            publisherConsent: str("IABTCF_PublisherConsent"),
            publisherLegitimateInterests: str("IABTCF_PublisherLegitimateInterests"),
            publisherCC: str("IABTCF_PublisherCC"),
            purposeOneTreatment: int("IABTCF_PurposeOneTreatment", 0) == 1,
            cmpId: int("IABTCF_CmpSdkID", 0),
            tcfPolicyVersion: int("IABTCF_PolicyVersion", 2)
        )
    }

    /// Whether analytics collection/sending is permitted under the current consent.
    ///
    /// The SDK stores a visitor ID and sends measurement events, which fall under TCF Purpose 1
    /// (store and/or access information on a device). Analytics is suppressed **only** when a CMP
    /// has positively signalled that GDPR applies *and* Purpose 1 consent is not granted. With no
    /// CMP present (no TCF data) or when GDPR does not apply, analytics runs as before, so a
    /// publisher without a CMP is not silently regressed.
    static var analyticsAllowed: Bool {
        let defaults = UserDefaults.standard
        // `IABTCF_gdprApplies` is stored as an Int (1/0); nil = the key is absent.
        let gdprApplies: Int? = defaults.object(forKey: Key.gdprApplies) != nil
            ? defaults.integer(forKey: Key.gdprApplies)
            : nil
        let purposeConsents = defaults.string(forKey: Key.purposeConsents)
        return analyticsDecision(gdprApplies: gdprApplies, purposeConsents: purposeConsents)
    }

    /// Pure consent decision, split out from storage so it is unit-testable.
    ///
    /// - Parameters:
    ///   - gdprApplies: value of `IABTCF_gdprApplies` (1 = applies, 0 = does not), or `nil` when absent.
    ///   - purposeConsents: value of `IABTCF_PurposeConsents` (a "1"/"0" string per purpose), or `nil`.
    /// - Returns: `true` unless GDPR positively applies and Purpose 1 consent is not granted.
    static func analyticsDecision(gdprApplies: Int?, purposeConsents: String?) -> Bool {
        // GDPR positively applies only when the key is present and == 1.
        guard gdprApplies == 1 else { return true }
        // GDPR applies: require Purpose 1 consent; suppress if it cannot be confirmed.
        return hasPurposeConsent(purposeConsents, 1)
    }

    /// Reads bit `purpose` (1-indexed) from a `IABTCF_PurposeConsents`-style "1"/"0" string.
    /// Returns `false` when the string is missing or the purpose is not granted.
    private static func hasPurposeConsent(_ consents: String?, _ purpose: Int) -> Bool {
        guard let consents = consents, purpose >= 1, purpose <= consents.count else { return false }
        let index = consents.index(consents.startIndex, offsetBy: purpose - 1)
        return consents[index] == "1"
    }
}
