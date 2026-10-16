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

    /// Whether GDPR applies. `1` = applies, `0` = does not. Absent (or an unreadable/wrongly-typed
    /// value) but a TC string exists → applies, rather than silently treating it as non-applicable.
    static var gdprApplies: Bool {
        if let v = gdprAppliesInt { return v == 1 }
        return tcString != nil
    }

    /// Reads `IABTCF_gdprApplies` robustly: a Number (standard) or a mistyped String. Returns `nil`
    /// when the key is absent or cannot be interpreted.
    static var gdprAppliesInt: Int? {
        guard let obj = UserDefaults.standard.object(forKey: Key.gdprApplies) else { return nil }
        if let n = obj as? NSNumber { return n.intValue == 1 ? 1 : 0 }
        if let s = (obj as? String)?.trimmingCharacters(in: .whitespaces).lowercased() {
            if s == "1" || s == "true" { return 1 }
            if s == "0" || s == "false" { return 0 }
        }
        return nil
    }

    /// Whether a CMP has written any TCF data, so the bridge should be installed/kept updated.
    static var hasCmpData: Bool {
        tcString != nil || UserDefaults.standard.object(forKey: Key.gdprApplies) != nil
    }

    /// A snapshot to push on a consent change: the real decoded one, or an explicit cleared
    /// (all-denied / honouring GDPR-applies) state when the TC string has been removed — so the
    /// live page never silently retains the previous grant.
    static var updateSnapshot: TcfSnapshot {
        if let real = tcfSnapshot { return real }
        let d = UserDefaults.standard
        func int(_ key: String, _ fallback: Int) -> Int {
            d.object(forKey: key) != nil ? d.integer(forKey: key) : fallback
        }
        return buildTcData(TcfInputs(
            tcString: "",
            gdprApplies: gdprApplies,
            purposeConsents: "", purposeLegitimateInterests: "",
            vendorConsents: "", vendorLegitimateInterests: "",
            specialFeatureOptIns: "", publisherConsent: "", publisherLegitimateInterests: "",
            publisherCustomConsents: "", publisherCustomLegitimateInterests: "",
            publisherRestrictions: [:], publisherCC: "",
            purposeOneTreatment: false,
            cmpId: int("IABTCF_CmpSdkID", 0),
            cmpVersion: int("IABTCF_CmpSdkVersion", 1),
            tcfPolicyVersion: int("IABTCF_PolicyVersion", 4)
        ))
    }

    /// Raw decoded IAB TCF v2 values read from storage, fed to ``buildTcData(_:)``.
    struct TcfInputs {
        let tcString: String
        let gdprApplies: Bool
        let purposeConsents: String?
        let purposeLegitimateInterests: String?
        let vendorConsents: String?
        let vendorLegitimateInterests: String?
        let specialFeatureOptIns: String?
        let publisherConsent: String?
        let publisherLegitimateInterests: String?
        let publisherCustomConsents: String?
        let publisherCustomLegitimateInterests: String?
        /// purposeId → per-vendor restriction string ('0'/'1'/'2' = type, other char = none).
        let publisherRestrictions: [Int: String]
        let publisherCC: String
        let purposeOneTreatment: Bool
        let cmpId: Int
        let cmpVersion: Int
        let tcfPolicyVersion: Int
    }

    /// A ready-to-inject TCData JSON payload plus whether the CMP snapshot is complete.
    struct TcfSnapshot {
        let json: String
        let ready: Bool
    }

    /// Builds an IAB TCF v2.2 `TCData` object (as JSON) from decoded CMP values. Pure, so it is
    /// unit-testable without storage. See the Android `buildTcData` for the shared contract:
    /// 1-based `{id: bool}` maps, missing grants never defaulted to granted, publisher restrictions
    /// parsed into `{purposeId: {vendorId: type}}` (non-`0/1/2` chars dropped), `ready`/`cmpuishown`
    /// when decoded grants are not yet written, and no fabricated GVL metadata.
    static func buildTcData(_ inp: TcfInputs) -> TcfSnapshot {
        // The required decoded grants Prebid reads are purpose AND vendor consents; if either is
        // not yet written the CMP is mid-update, so the snapshot is not ready.
        let ready = inp.purposeConsents != nil && inp.vendorConsents != nil

        func bits(_ s: String?) -> [String: Bool] {
            guard let s = s else { return [:] }
            var o: [String: Bool] = [:]
            for (i, c) in s.enumerated() { o[String(i + 1)] = (c == "1") }
            return o
        }

        var restrictions: [String: [String: Int]] = [:]
        for (purpose, s) in inp.publisherRestrictions {
            var entry: [String: Int] = [:]
            for (i, c) in s.enumerated() where c == "0" || c == "1" || c == "2" {
                entry[String(i + 1)] = Int(String(c))!
            }
            if !entry.isEmpty { restrictions[String(purpose)] = entry }
        }

        let publisher: [String: Any] = [
            "consents": bits(inp.publisherConsent),
            "legitimateInterests": bits(inp.publisherLegitimateInterests),
            "customPurpose": [
                "consents": bits(inp.publisherCustomConsents),
                "legitimateInterests": bits(inp.publisherCustomLegitimateInterests),
            ],
            "restrictions": restrictions,
        ]

        let tcData: [String: Any] = [
            "tcString": inp.tcString,
            "gdprApplies": inp.gdprApplies,
            "eventStatus": ready ? "tcloaded" : "cmpuishown",
            "cmpStatus": "loaded",
            "cmpId": inp.cmpId,
            "cmpVersion": inp.cmpVersion,
            "tcfPolicyVersion": inp.tcfPolicyVersion,
            "isServiceSpecific": true,
            "purposeOneTreatment": inp.purposeOneTreatment,
            "publisherCC": inp.publisherCC,
            "purpose": [
                "consents": bits(inp.purposeConsents),
                "legitimateInterests": bits(inp.purposeLegitimateInterests),
            ],
            "vendor": [
                "consents": bits(inp.vendorConsents),
                "legitimateInterests": bits(inp.vendorLegitimateInterests),
            ],
            "specialFeatureOptins": bits(inp.specialFeatureOptIns),
            "publisher": publisher,
        ]

        let data = (try? JSONSerialization.data(withJSONObject: tcData, options: [.sortedKeys])) ?? Data("{}".utf8)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return TcfSnapshot(json: json, ready: ready)
    }

    /// Reads the full decoded TCF consent from storage and builds a snapshot, or `nil` when no
    /// TC string is stored.
    static var tcfSnapshot: TcfSnapshot? {
        guard let tc = tcString else { return nil }
        let d = UserDefaults.standard
        func str(_ key: String) -> String? { d.string(forKey: key) }
        func int(_ key: String, _ fallback: Int) -> Int {
            d.object(forKey: key) != nil ? d.integer(forKey: key) : fallback
        }
        var restrictions: [Int: String] = [:]
        for purpose in 1...24 {
            if let s = str("IABTCF_PublisherRestrictions\(purpose)"), !s.isEmpty { restrictions[purpose] = s }
        }
        return buildTcData(TcfInputs(
            tcString: tc,
            gdprApplies: gdprApplies,
            purposeConsents: str(Key.purposeConsents),
            purposeLegitimateInterests: str("IABTCF_PurposeLegitimateInterests"),
            vendorConsents: str("IABTCF_VendorConsents"),
            vendorLegitimateInterests: str("IABTCF_VendorLegitimateInterests"),
            specialFeatureOptIns: str("IABTCF_SpecialFeaturesOptIns"),
            publisherConsent: str("IABTCF_PublisherConsent"),
            publisherLegitimateInterests: str("IABTCF_PublisherLegitimateInterests"),
            publisherCustomConsents: str("IABTCF_PublisherCustomPurposesConsents"),
            publisherCustomLegitimateInterests: str("IABTCF_PublisherCustomPurposesLegitimateInterests"),
            publisherRestrictions: restrictions,
            publisherCC: str("IABTCF_PublisherCC") ?? "",
            purposeOneTreatment: int("IABTCF_PurposeOneTreatment", 0) == 1,
            cmpId: int("IABTCF_CmpSdkID", 0),
            cmpVersion: int("IABTCF_CmpSdkVersion", 1),
            tcfPolicyVersion: int("IABTCF_PolicyVersion", 4)
        ))
    }

    /// Whether analytics collection/sending is permitted under the current consent.
    ///
    /// The SDK stores a visitor ID and sends measurement events, which fall under TCF Purpose 1
    /// (store and/or access information on a device). Analytics is suppressed **only** when a CMP
    /// has positively signalled that GDPR applies *and* Purpose 1 consent is not granted. With no
    /// CMP present (no TCF data) or when GDPR does not apply, analytics runs as before, so a
    /// publisher without a CMP is not silently regressed.
    static var analyticsAllowed: Bool {
        // Read the flag robustly; if it is present but unreadable/wrongly-typed, fall back to
        // "applies" whenever a TC string exists rather than silently allowing analytics.
        let gdprApplies: Int? = gdprAppliesInt ?? (tcString != nil ? 1 : nil)
        let purposeConsents = UserDefaults.standard.string(forKey: Key.purposeConsents)
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
