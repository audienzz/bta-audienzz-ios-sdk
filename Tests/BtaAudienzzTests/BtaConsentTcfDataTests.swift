import XCTest
@testable import BtaAudienzz

/// Unit tests for the pure TCData builder `BtaConsent.buildTcData` — the JSON served through the
/// `__tcfapi` bridge. Mirrors the Android `BtaConsentTcfDataTest`.
final class BtaConsentTcfDataTests: XCTestCase {

    private func inputs(
        purposeConsents: String? = "1111111111",
        purposeLI: String? = "",
        vendorConsents: String? = "",
        vendorLI: String? = "",
        specialFeatures: String? = "",
        publisherConsent: String? = "",
        publisherLI: String? = "",
        customConsents: String? = "",
        customLI: String? = "",
        restrictions: [Int: String] = [:],
        publisherCC: String = "CH",
        purposeOneTreatment: Bool = false,
        cmpId: Int = 10,
        cmpVersion: Int = 7,
        policyVersion: Int = 4
    ) -> BtaConsent.TcfInputs {
        BtaConsent.TcfInputs(
            tcString: "CPtest",
            gdprApplies: true,
            purposeConsents: purposeConsents,
            purposeLegitimateInterests: purposeLI,
            vendorConsents: vendorConsents,
            vendorLegitimateInterests: vendorLI,
            specialFeatureOptIns: specialFeatures,
            publisherConsent: publisherConsent,
            publisherLegitimateInterests: publisherLI,
            publisherCustomConsents: customConsents,
            publisherCustomLegitimateInterests: customLI,
            publisherRestrictions: restrictions,
            publisherCC: publisherCC,
            purposeOneTreatment: purposeOneTreatment,
            cmpId: cmpId,
            cmpVersion: cmpVersion,
            tcfPolicyVersion: policyVersion
        )
    }

    private func build(_ inp: BtaConsent.TcfInputs) -> [String: Any] {
        let snap = BtaConsent.buildTcData(inp)
        let obj = try! JSONSerialization.jsonObject(with: Data(snap.json.utf8)) as! [String: Any]
        return obj
    }

    func testPurposeAndVendorConsentsMap1Based() {
        let d = build(inputs(purposeConsents: "101", vendorConsents: "0110"))
        let pc = (d["purpose"] as! [String: Any])["consents"] as! [String: Bool]
        XCTAssertEqual(pc["1"], true); XCTAssertEqual(pc["2"], false); XCTAssertEqual(pc["3"], true)
        let vc = (d["vendor"] as! [String: Any])["consents"] as! [String: Bool]
        XCTAssertEqual(vc["1"], false); XCTAssertEqual(vc["2"], true)
        XCTAssertEqual(vc["3"], true); XCTAssertEqual(vc["4"], false)
    }

    func testMissingGrantsAreEmptyNeverTrue() {
        let d = build(inputs(purposeLI: nil, vendorConsents: nil))
        XCTAssertTrue(((d["vendor"] as! [String: Any])["consents"] as! [String: Bool]).isEmpty)
        XCTAssertTrue(((d["purpose"] as! [String: Any])["legitimateInterests"] as! [String: Bool]).isEmpty)
    }

    func testAbsentPurposeConsentsNotReadyCmpuishown() {
        let snap = BtaConsent.buildTcData(inputs(purposeConsents: nil))
        XCTAssertFalse(snap.ready)
        let d = try! JSONSerialization.jsonObject(with: Data(snap.json.utf8)) as! [String: Any]
        XCTAssertEqual(d["eventStatus"] as? String, "cmpuishown")
    }

    func testPresentPurposeConsentsReadyTcloaded() {
        let snap = BtaConsent.buildTcData(inputs(purposeConsents: ""))
        XCTAssertTrue(snap.ready)
        let d = try! JSONSerialization.jsonObject(with: Data(snap.json.utf8)) as! [String: Any]
        XCTAssertEqual(d["eventStatus"] as? String, "tcloaded")
        XCTAssertTrue(((d["purpose"] as! [String: Any])["consents"] as! [String: Bool]).isEmpty)
    }

    func testPublisherRestrictionPreservesTypeAndDropsNonRestricted() {
        let restr = String(repeating: "_", count: 31) + "0"
        let d = build(inputs(restrictions: [2: restr]))
        let r = (d["publisher"] as! [String: Any])["restrictions"] as! [String: Any]
        let p2 = r["2"] as! [String: Int]
        XCTAssertEqual(p2["32"], 0)
        XCTAssertNil(p2["1"]) // '_' → no restriction
    }

    func testRestrictionTypes1And2() {
        let d = build(inputs(restrictions: [1: "12"]))
        let r = ((d["publisher"] as! [String: Any])["restrictions"] as! [String: Any])["1"] as! [String: Int]
        XCTAssertEqual(r["1"], 1)
        XCTAssertEqual(r["2"], 2)
    }

    func testSpecialFeaturesAndCustomPurposesMapped() {
        let d = build(inputs(specialFeatures: "10", customConsents: "01"))
        let sf = d["specialFeatureOptins"] as! [String: Bool]
        XCTAssertEqual(sf["1"], true); XCTAssertEqual(sf["2"], false)
        let cp = ((d["publisher"] as! [String: Any])["customPurpose"] as! [String: Any])["consents"] as! [String: Bool]
        XCTAssertEqual(cp["1"], false); XCTAssertEqual(cp["2"], true)
    }

    func testMetadataFromInputsNoFabricatedGvlVersion() {
        let d = build(inputs(cmpId: 42, cmpVersion: 9, policyVersion: 4))
        XCTAssertEqual(d["cmpId"] as? Int, 42)
        XCTAssertEqual(d["cmpVersion"] as? Int, 9)
        XCTAssertEqual(d["tcfPolicyVersion"] as? Int, 4)
        XCTAssertNil(d["gvlVersion"], "gvlVersion must not be fabricated")
        XCTAssertNotNil(d["useNonStandardTexts"], "TCF 2.2 field")
        XCTAssertNil(d["useNonStandardStacks"], "TCF 2.0 field should be gone")
    }
}
